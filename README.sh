# Repository containing juju bundles to provision openstack cloud

# Remember to add sudo where required
# Install MAAS 
apt-add-repository ppa:maas/3.5
apt-get update
apt-get -y install maas jq curl

systemctl disable --now systemd-timesyncd

# MAAS init
maas init region+rack
maas create admin 
maas status

# Automated MAAS init
# maas createadmin --username maasadmin --password admin --email admin

# Configure MAAS
export APIKEY=$(maas apikey --username maasadmin)
# env | grep API #to get API Key for MAAS
maas login maasadmin 'http://localhost:5240/MAAS/' $APIKEY 
maas maasadmin status
maas maasadmin ipranges read | jq
maas maasadmin maas set-config

# MAAS Network Configuration using CLI
# maas maasadmin subnet update 192.168.50.0/24 gateway_ip=192.168.50.1
# maas maasadmin ipranges create type=dynamic start_ip=192.168.92.0 end_ip=192.168.92.200
# Add SSH Public Key in Maas for adding it during provision to all machines
# maas maasadmin sshkeys create "key=$(cat ~/.ssh/id_rsa.pub)"

# Install LXD and JUJU
snap refresh lxd
snap install lxd --channel=5.21/stable
snap install juju --classic

# Add MAAS Cloud to JUJU
juju add-cloud --local maas-cloud maascloud.yml 
juju add-cloud maas-cloud maascloud.yml 
juju list-clouds
juju add-credential maas-cloud
juju list-credentials
juju clouds
juju clouds --local
juju credentials
juju models

# Bootstrap JUJU Controller as LXD VM in MAAS Cloud
# Remember to create manually a LXD VM for Juju Controller with tag juju-controller
juju bootstrap maas-cloud --controller-charm-channel=3.6/stable --bootstrap-series=jammy --bootstrap-constraints "tags=jujucontroller mem=2G" --debug
juju controllers
juju status --color
juju clouds --all
juju models

juju add-model --config default-series=jammy opeshnstack
juju switch openstack
juju add-ssh-key "$(cat ~/.ssh/id_rsa.pub)"
juju deploy ./openjam.yaml

# To watch the progress run
watch -c juju status --color --relations

# Configure Vault when vault unit is ready but require initialization
snap install vault
export VAULT_ADDR="http://UNITIPADDRESS:8200"
vault operator init -key-shares=5 -key-threshold=3
vault operator unseal
vault operator unseal
vault operator unseal
export VAULT_TOKEN=root_token_received_after_vault_init
vault token create -ttl=10m
juju run vault/leader authorize-charm token=newroottoken
juju run vault/leader generate-root-ca

# Get Dashboard IP and Admin passwords
juju status --format=yaml openstack-dashboard | grep public-address | awk '{print $2}' | head -1
juju run keystone/0 get-admin-password

# Login to openstack in a browser with user 'admin' and password from above and domain 'admin_domain'
# You can also operate on openstack using CLI like in file openstack_config.sh

# Inside Nodes (Not required)
# fstrim -a
# swapoff -a
# systemctl disable swap.target
# rm -rf /swap.img 
# sysctl vm.swappiness=10
# modprobe br_netfilter
# sysctl -w net.ipv4.ip_forward=1

# To destroy the environment type:
# juju destroy-model openstack --destroy-storage --force

# To destroy the controller type:
# juju destroy-controller maas-cloud --destroy-all-models

# Sample juju scp command
# juju scp vault/1:/home/ubuntu/config ~/config