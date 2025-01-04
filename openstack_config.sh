snap install openstackclients 
source openrc 
openstack
openstack service list


# First download a boot image, like Focal amd64:
    curl http://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img \
       --output ~/cloud-images/focal-amd64.img

# Now import the image and call it 'focal-amd64':
openstack image create --public --container-format bare \
       --disk-format qcow2 --file ~/cloud-images/focal-amd64.img \
       focal-amd64
openstack network create --external \
   --provider-network-type flat --provider-physical-network physnet1 \
   ext_net

# When creating the external subnet ('ext_subnet') the actual values used will depend on the environment that the second network interface (on all nodes) is connected to:

openstack subnet create --network ext_net --no-dhcp \
   --gateway 10.0.0.1 --subnet-range 10.0.0.0/21 \
   --allocation-pool start=10.0.0.10,end=10.0.0.200 \
   ext_subnet
# Note: For a public cloud the ports would be connected to a publicly addressable part of the internet.

# We'll also need an internal network ('int_net'), subnet ('int_subnet'), and router ('provider-router'):
# openstack network create int_net
openstack subnet create --network int_net --dns-nameserver 8.8.8.8 \
   --gateway 192.168.0.1 --subnet-range 192.168.0.0/24 \
   --allocation-pool start=192.168.0.10,end=192.168.0.200 \
   int_subnet

openstack router create provider-router
openstack router set --external-gateway ext_net provider-router
openstack router add subnet provider-router int_subnet

# Create a flavor
openstack flavor create --ram 2048 --disk 20 --ephemeral 20 m1.small

## Configure security groups
# To allow ICMP (ping) and SSH traffic to flow to cloud instances create
# corresponding rules for each existing security group:
    for i in $(openstack security group list | awk '/default/{ print $2 }'); do
       openstack security group rule create $i --protocol icmp --remote-ip 0.0.0.0/0;
       openstack security group rule create $i --protocol tcp --remote-ip 0.0.0.0/0 --dst-port 22;
    done

# You only need to perform this step once.

## Create an instance
# Create a Focal amd64 instance called 'focal-1':
    openstack server create --image focal-amd64 --flavor m1.small \
       --key-name mykey --network int_net \
        focal-1

## Assign a floating IP address
# Request and assign a floating IP address to the new instance:
    FLOATING_IP=$(openstack floating ip create -f value -c floating_ip_address ext_net)
    openstack server add floating ip focal-1 $FLOATING_IP

# Log in to the new instance:
    ssh -i ~/cloud-keys/id_mykey ubuntu@$FLOATING_IP

# The below commands are a good start to troubleshooting if something goes wrong:
    openstack console log show focal-1
    openstack server show focal-1