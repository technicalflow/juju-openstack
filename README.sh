# Juju runbook for provisioning an OpenStack cloud.
# Run these commands manually from this directory; most require root privileges.

# Keep storage layouts consistent across computers; this example expects a free /dev/sda.

# Install LXD and MAAS.
snap refresh
snap install lxd --channel=5.21/stable

add-apt-repository ppa:maas/3.6
apt-get install --yes maas jq curl

systemctl disable --now systemd-timesyncd

# MAAS initialization.
maas init region+rack
maas createadmin
maas status

# Non-interactive alternative. Use a strong, non-default password.
# maas createadmin --username maasadmin --password '<strong-password>' --email admin@example.com

# Configure MAAS.
export APIKEY="$(maas apikey --username maasadmin)"
# To inspect the API key, use: env | grep '^APIKEY='
maas login maasadmin 'http://localhost:5240/MAAS/' "$APIKEY"
maas maasadmin status
maas maasadmin ipranges read | jq .
maas maasadmin maas set-config

# Increase the regiond worker count.
maas maasadmin maas set-config regiond.numworkers=2

# MAAS network configuration using the CLI.
# maas maasadmin subnet update 192.168.50.0/24 gateway_ip=192.168.50.1
# maas maasadmin ipranges create type=dynamic start_ip=192.168.92.0 end_ip=192.168.92.200
# Add an SSH public key so it is installed on provisioned machines.
# maas maasadmin sshkeys create "key=$(cat ~/.ssh/id_rsa.pub)"

# LXD and BIND coexistence: restrict BIND to the host's first global IPv4 address.
# Back up this file before applying the configuration change.
cp /etc/bind/named.conf.options /etc/bind/named.conf.options.bak
IP="$(ip -4 -o addr show scope global | awk 'NR == 1 { sub(/\/.*/, "", $4); print $4 }')"
test -n "$IP" || { echo "Could not determine a global IPv4 address." >&2; return 1 2>/dev/null || exit 1; }
sed -i 's/listen-on-v6 { any; };/listen-on-v6 { none; };/' /etc/bind/named.conf.options
grep -qF "listen-on { $IP; };" /etc/bind/named.conf.options ||
  sed -i "/listen-on-v6 { none; };/a\\listen-on { $IP; };" /etc/bind/named.conf.options

# Install Juju.
snap install juju --classic

# Add the MAAS cloud to Juju.
juju add-cloud maas-cloud maascloud.yaml
juju list-clouds
juju add-credential maas-cloud
juju list-credentials
juju clouds
juju clouds --local
juju credentials
juju models

# Bootstrap the Juju controller.
# For a controller hosted in MAAS, first create an LXD VM tagged juju-controller.
# juju bootstrap maas-cloud name=jujucontroller --bootstrap-series=noble --bootstrap-constraints "tags=juju mem=4G" --debug
# To provision the controller locally in an LXC container instead:
juju bootstrap localhost jujucontroller --bootstrap-series=noble --bootstrap-constraints "cores=4 mem=4G" --debug
juju controllers
juju status --color
juju clouds --all
juju models

juju add-model --config default-series=jammy openstack
juju switch openstack
juju add-ssh-key "$(cat ~/.ssh/id_rsa.pub)"
juju deploy "./juju deployment/openjam.yaml"

# Watch deployment progress.
watch -c juju status --color --relations

# Configure Vault after the vault unit is ready; initialization produces recovery keys.
snap install vault
# export VAULT_ADDR="http://vault/leader:8200"
export VAULT_ADDR="http://$(juju status vault/leader --format=yaml | awk '/public-address/ { print $2 }' | sed -n '2{p;q}'):8200"

vault operator init -key-shares=5 -key-threshold=3
vault operator unseal
vault operator unseal
vault operator unseal
# Set this to the root token returned by `vault operator init`.
export VAULT_TOKEN=root_token_received_after_vault_init
export VAULT_CHARM_TOKEN="$(vault token create -format=json -ttl=10m | jq -r '.auth.client_token')"
test -n "$VAULT_CHARM_TOKEN" && test "$VAULT_CHARM_TOKEN" != null ||
  { echo "Vault did not return a charm token." >&2; return 1 2>/dev/null || exit 1; }
juju run vault/leader authorize-charm token="$VAULT_CHARM_TOKEN"
juju run vault/leader generate-root-ca

# Get the dashboard IP address and administrator password.
juju status --format=yaml openstack-dashboard | grep public-address | awk '{print $2}' | head -1
juju run keystone/0 get-admin-password

# Log in to OpenStack in a browser as admin using the password above and domain admin_domain.
# OpenStack CLI examples are in openstack_config.sh.

# Optional node cleanup (run inside nodes only).
# fstrim -a
# swapoff -a
# systemctl disable swap.target
# rm -rf /swap.img 
# sysctl vm.swappiness=10
# modprobe br_netfilter
# sysctl -w net.ipv4.ip_forward=1

# Destructive: destroy the OpenStack model and its storage.
# juju destroy-model openstack --destroy-storage --force

# Destructive: destroy the controller and all its models.
# juju destroy-controller maas-cloud --destroy-all-models

# Copy a file from a Juju unit.
# juju scp vault/1:/home/ubuntu/config ~/config

# Cloud-init example for worker nodes.
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

# Add a VM for the Juju controller in MAAS from the command line.
# First identify the MAAS VM host, then compose a minimally sized VM.
# export VM_HOST_ID=$(maas maasadmin vm-hosts read | jq '.[] | select(.name=="maaslxd") | .id')
# maas maasadmin vm-host compose $VM_HOST_ID cores=2 memory=4096 architecture="amd64/generic"  storage="main:16(pool1)" hostname="jujucontroller"
# # Allow high CPU oversubscription so all VMs can use all cores.
# maas maasadmin vm-host update $VM_HOST_ID cpu_over_commit_ratio=4

# Add LXD to Juju.
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

# Add the Landscape client.
# landscape-config --computer-title "sv-upsilon" --account-name standalone  --url https://192.168.92.11/message-system --ssl-public-key=/etc/landscape/landscape.crt --tags=server -p pineapple1
# curl https://landscape.maas/ping

# Recover the MySQL cluster after a complete outage.
# juju run mysql-innodb-cluster/1 reboot-cluster-from-complete-outage


# MAAS on libvirt.
# Test access as the maas user so it matches MAAS's permissions.
# sudo -H -u maas virsh -c qemu+ssh://you@<host-where-vm-is>/system list --all

# If using the power address qemu:///system, add maas to the libvirt group.
# # grep ^libvirtd /etc/group
# libvirtd:x:112:maas
# Reboot after applying this change as existing processes won't be in the new extra group.

# Add these kernel parameters to hardware-node tags:
# intel_iommu=on iommu=pt kvm_intel.nested=1