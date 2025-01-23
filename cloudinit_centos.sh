#cloud-config
users:
  - name: madmin
    ssh_authorized_keys:
      - ssh-rsa key
    lock_passwd: false
    passwd: $encoded
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    groups: sudo
    shell: /bin/bash
runcmd:
  - sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
  - sed -i 's/mirrorlist/#mirrorlist/g'  /etc/yum.repos.d/CentOS-*
  - dnf swap -y centos-{linux,stream}-repos
  - sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
  - sed -i 's/mirrorlist/#mirrorlist/g'  /etc/yum.repos.d/CentOS-*
  - dnf distro-sync -y --best --allowerasing
packages:
  - git
  - htop
  - curl
  - wget
  - make
  - gcc
  - automake
  - autoconf
  - nano
