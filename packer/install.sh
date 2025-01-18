#!/bin/bash

set -e

# Install required packages
sudo apt install -y qemu-system qemu-utils debootstrap pip libnbd-bin nbdkit fuse2fs cifs-utils ovmf cloud-image-utils parted

# Install packer
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install -y packer
sudo packer plugins install github.com/hashicorp/qemu

# Clone the packer-maas repository
git clone https://github.com/canonical/packer-maas.git
cd packer-maas/ol9

# For Azure Linux edit mariner-packer.pkr.hcl to change the image name and add /usr/share/ovmf/OVMF.fd in the boot_command

# Build the image
sudo packer init .
sudo PACKER_LOG=1 packer build

# Add image to MAAS
maas madmin boot-resources create \
    name='ol/9.5' title='Oracle Linux 9.5' \
    architecture='amd64/generic' filetype='tgz' \
    content@=ol9.tar.gz