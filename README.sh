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

# Configure MAAS
export APIKEY=$(maas apikey --username madmin)
maas login madmin 'http://localhost:5240/MAAS/' $APIKEY 
maas madmin status
maas madmin ipranges read | jq
maas madmin maas set-config

# Install LXD and JUJU
snap refresh lxd
snap install lxd --channel=5.21/stable
snap install juju --classic

# Add MAAS Cloud to JUJU
juju add-cloud --local maas-cloud maascloud.yml 
juju add-cloud maas-cloud maascloud.yml 
juju list-clouds
juju add-credential maas-cloud
juju clouds
juju clouds --local
juju credentials
juju models

# Bootstrap JUJU Controller as LXD VM in MAAS Cloud
juju bootstrap maas-cloud --controller-charm-channel=3.6/stable --bootstrap-series=jammy --bootstrap-constraints "tags=jujucontroller mem=2G" --debug
juju clouds --all
juju models

juju add-model --config default-series=jammy openstack
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
export VAULT_TOKEN=roottokenreceivedafterinit
vault token create -ttl=10m
juju run vault/leader authorize-charm token=newroottoken
juju run vault/leader generate-root-ca

# Get Dashboard IP and Admin passwords
juju status --format=yaml openstack-dashboard | grep public-address | awk '{print $2}' | head -1
juju run keystone/0 get-admin-password

# Login in a browser with user 'admin' and password from above and domain 'admin_domain'



# Inside Nodes (Not required)
# apt remove -y iwl* ipw* bluez* alsa* b43* xdg* modemmanager 
# apt update && apt upgrade -y && apt autoremove -y
# export LANGUAGE=en_US.UTF-8
# export LANG=en_US.iso-8859-2
# export LC_ALL=en_US.UTF-8
# systemctl disable bluetooth.target 
# systemctl disable vmtoolsd.service
# fstrim -a
# swapoff -a
# systemctl disable swap.target
# rm -rf /swap.img 
# sysctl vm.swappiness=10

# modprobe br_netfilter
# sysctl net.ipv4.ip_forward=1s
# touch /etc/sysctl.d/10-addin.conf
# tee /etc/sysctl.d/10-addin.conf<<EOF
# net.ipv4.ip_forward = 1
# EOF

# MTU experiments
# ip link set dev eth0 mtu 1500
# ip link set dev eno1 mtu 1500
# ip link set dev br-eno1 mtu 1500
# sed -i 's/mtu: 9000/mtu: 1500/' /etc/netplan/99-juju.yaml
# nano /etc/netplan/99-juju.yaml
# for i in $(lxc list -c ns,config:image.os | grep -i "running" | awk '{print $2}'); do lxc exec $i ip link set dev eth0 mtu 1500; done for i in $(lxc list -c ns,config:image.os | grep -i "running" | awk '{print $2}'); do lxc exec $i ip link; done
# lxc list -c ns,config:image.os | grep -i "running" | awk '{print $2}'
