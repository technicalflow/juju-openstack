# Repository containing juju bundles to provision openstack cloud

# Recommending to keep similar storage setting across all computer - example have free /dev/sda

# First install LXD
snap refresh
snap install lxd --channel=5.21/stable

# Remember to add sudo where required
# Install MAAS 
apt-add-repository ppa:maas/3.6
apt-get -y install maas jq curl

systemctl disable --now systemd-timesyncd

# MAAS init
maas init region+rack
maas createadmin 
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

# Add regiond numworkers to 2
maas maasadmin maas set-config regiond.numworkers=2

# MAAS Network Configuration using CLI
# maas maasadmin subnet update 192.168.50.0/24 gateway_ip=192.168.50.1
# maas maasadmin ipranges create type=dynamic start_ip=192.168.92.0 end_ip=192.168.92.200
# Add SSH Public Key in Maas for adding it during provision to all machines
# maas maasadmin sshkeys create "key=$(cat ~/.ssh/id_rsa.pub)"

# LXC/LXD FIX for fixing avahi-deamon and dnsmasq used by LXD with coexistence with BIND in MAAS
IP=$(ip -4 addr show scope global | grep inet | head -n1 | awk '{print $2}' | cut -d/ -f1)
sed -i 's/listen-on-v6 { any; };/listen-on-v6 { none; };/' /etc/bind/named.conf.options
sed -i "/listen-on-v6 { none; };/a\\listen-on { $IP; };" /etc/bind/named.conf.options

# Install JUJU
snap install juju --classic

# Add MAAS Cloud to JUJU
juju add-cloud maas-cloud maascloud.yaml
juju list-clouds
juju add-credential maas-cloud
juju list-credentials
juju clouds
juju clouds --local
juju credentials
juju models

# Bootstrap JUJU Controller as LXD VM in MAAS Cloud
# Remember to create manually a LXD VM for Juju Controller with tag juju-controller
juju bootstrap maas-cloud name=jujucontroller --controller-charm-channel=3.6/stable --bootstrap-series=jammy --bootstrap-constraints "tags=juju mem=4G" --debug
juju controllers
juju status --color
juju clouds --all
juju models

juju add-model --config default-series=jammy openstack
juju switch openstack
juju add-ssh-key "$(cat ~/.ssh/id_rsa.pub)"
juju deploy ./openjam.yaml

# To watch the progress run
watch -c juju status --color --relations

# Configure Vault when vault unit is ready but require initialization
snap install vault
# export VAULT_ADDR="http://vault/leader:8200"
export VAULT_ADDR=http://$(juju status vault/leader --format=yaml | awk '/public-address/ { print $2 }' | sed -n '2{p;q}'):8200

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

# Cloud Init for Worker Nodes
# #cloud-config
# package_update: true
# package_upgrade: true
# packages:
#   - curl
#   - nano
#   - htop
# locale: en_GB.UTF-8
# timezone: Europe/Warsaw
# runcmd:
#   - [touch, /tmp/one]
#   - [swapoff, -a]
#   - [rm, -rf /swap.img]
#   - [sed, -i '/swap/s/^/#/' /etc/fstab]
#   - [echo, net.ipv4.ip_unprivileged_port_start=80 >> /etc/sysctl.conf]
#   - [reboot]

# maasmod: ["sh", "-c", "echo === Start Customization Scripts ==="]
# maasmod: ["curtin", "in-target", "--", "sh", "-c", "sudo swapoff -a"]
# maasmod: ["curtin", "in-target", "--", "sh", "-c", "sudo rm -rf /swap.img"]
# maasmod: ["curtin", "in-target", "--", "sh", "-c", "sed -i '/swap/s/^/#/' /etc/fstab"]
# maasmod: ["curtin", "in-target", "--", "sh", "-c", "echo net.ipv4.ip_unprivileged_port_start=80 | sudo tee -a /etc/sysctl.conf"]
# maasmod: ["curtin", "in-target", "--", "sh", "-c", "sudo systemctl stop swap.target"]
# maasmod: ["curtin", "in-target", "--", "sh", "-c", "sudo systemctl disable swap.target"]
# maasmod: ["curtin", "in-target", "--", "sh", "-c", "sudo fstrim -a"]
# maasmod: ["sh", "-c", "echo === Done Customization Scripts ==="]

# Adding a VM for the Juju Controller in MAAS from the command line
# add a VM for the juju controller with minimal memory
# export VM_HOST_ID=$(maas maasadmin vm-hosts read | jq '.[] | select(.name=="maaslxd") | .id')
# maas maasadmin vm-host compose $VM_HOST_ID cores=2 memory=4096 architecture="amd64/generic"  storage="main:16(pool1)" hostname="jujucontroller"
# # allow high CPU oversubscription so all VMs can use all cores
# maas maasadmin vm-host update $VM_HOST_ID cpu_over_commit_ratio=4

# Add LXD to JUJU
# cat << EOF > ~/lxd.yaml
# clouds:         # clouds key is required.
# lxd:
#   type: lxd
#   auth-types: [certificate]
#   endpoint: 192.168.92.210:8443
# EOF
# juju add-cloud lxdlocal
# juju add-credential lxd -f ~/lxd.yaml
# juju add-credential lxd
# juju add-model --config default-series=noble lxctests
# # lxc config device add juju-cb866e-1 eth1 nic name=eth1 nictype=bridged parent=br0

# Add landscape client
# landscape-config --computer-title "sv-upsilon" --account-name standalone  --url https://192.168.92.11/message-system --ssl-public-key=/etc/landscape/landscape.crt --tags=server -p pineapple1
# curl https://landscape.maas/ping

# Mysql Cluster after reboot
# juju run mysql-innodb-cluster/1 reboot-cluster-from-complete-outage