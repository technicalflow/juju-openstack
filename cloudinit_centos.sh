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
packages:
  - git
  - htop
  - curl
runcmd:
  - systemctl restart sshd
  - sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
  - sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - chown -R madmin:madmin /home/madmin/.ssh
  - chmod 700 -R /home/madmin/.ssh

# Upgrade Centos 8 to Centos 8 Stream
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-* && sed -i 's/mirrorlist/#mirrorlist/g'  /etc/yum.repos.d/CentOS-*
dnf distro-sync --best --allowerasing
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-* && sed -i 's/mirrorlist/#mirrorlist/g'  /etc/yum.repos.d/CentOS-*
dnf swap centos-{linux,stream}-repos

# Optional - not always work
# dnf install centos-release-stream -y --allowerasing
# dnf swap centos-{linux,stream}-repos
# dnf distro-sync --best --allowerasing
# reboot