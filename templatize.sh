#!/bin/bash
#
# Reconfigures the VM to be a proxmox template
#
set -euo pipefail

defaultUser=bcurnow
authorizedKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJMQ7gGnSRqhGbeiFm3MAfJ2DzJc3UMPBazhZIoXYLbKXaUFKPV2YuvTDeaXEa1UiAoxQJmhq94ABc2kPBfdfPSVd0elOKiKBbdpwO5PrKxK3DpxdX46GgKp0kRW8a3UgAUOuo0nigaEd7pWlkJ8+zxR0aFzfpbRiqIHTT8L3gVsRiQIrs0vkwn7sUMQs7ODJGz2bBuL6aI5aPyiyxoMlLfeo7AabnBIXCM5Bfym6m0/KmUkSugWyOgKXMCscBNiclC3QO/ExjouKnrlXQg9f/+I2J3FAex/QRRl1m7G1NPYygd1NIVcoNCIrU4g5aZkKqCk0DZC08mKVZ2zuRtqaluGMEfYd6LMGXSjuaFYDmtybvwEgvSlT9fkDCZcwF65YBnHXdr/QNWG4D5U3tXh5o4H202o6rsdsVhIsKIAkFqiiiC3yeCWiDVR2wQNENNkMbL/7tZMSqRm31iJjvQNuCBPpu6Z59DNkmZqb8dDgrOyi8SREBKf7FLuKx/jp7R4k= Brian.Curnow@T07M6PT2TT"
ansibleUser=ansible
# Same automation key installed by ansible/util/bootstrap.sh - kept in sync with that script
ansibleAuthorizedKey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICr9R4/zGU4rw1C1+MgWLy8yfUobxBK6Sd6hPPxp59/1 Ansible User Key"

# The following network settings reflect my own network. If you're using this script outside of
# it, change these values to match your own network before running it.
templateIp=10.2.12.224
templatePrefix=24
templateGateway=10.2.12.1
dnsServer1=10.2.5.10
dnsServer2=10.2.5.11
domain=internal.curnowtopia.com

cat <<EOF
Please ensure the following commands are run as ${defaultUser} before executing:

  set +o history # Turns off history for the current shell
  history -c     # Clears current history

This will ensure there's no extraneous command history when the template is cloned
EOF
read -p "Press any key to continue..." -n 1 -r

echo "Ensuring hostname is 'debian-template'"
echo "debian-template" | sudo tee /etc/hostname >/dev/null

echo "Updating /etc/hosts"
sudo tee /etc/hosts >/dev/null << EOF
127.0.0.1 debian-template.${domain} debian-template localhost # managed by ansible
EOF

echo "Clearing the machine id"
sudo rm -f /etc/machine-id

echo "Removing systemd-networkd configurations"
sudo rm -f /etc/systemd/network/*.network

echo "Setting up template systemd-networkd configuration"
sudo tee /etc/systemd/network/template.network >/dev/null << EOF
[Match]
Name=ens18

[Network]
Address=${templateIp}/${templatePrefix}
DNS=${dnsServer1}#dns1.${domain}
DNS=${dnsServer2}#dns2.${domain}
Domains=${domain}
Gateway=${templateGateway}
DNSOverTLS=yes

# The template has no machine-id (cleared below), which breaks the DHCPv6 client's ability to
# generate a DUID, and accepting RAs here would trigger DHCPv6. Rather than juggle that for a
# network that only needs to last long enough to run apt update, just disable IPv6 on this link
# entirely - IPv4 alone is enough to configure the template.
LinkLocalAddressing=ipv4
EOF

echo "Generating a new SSH keys"
sudo rm -f /etc/ssh/ssh_host_*
sudo ssh-keygen -A

echo "Clearing apt caches"
sudo apt-get autoremove -y
sudo apt-get clean -y
sudo apt-get autoclean -y

echo "Cleaning up users"
for user in ${defaultUser} ansible root
do
  echo "Clearing ${user} configuration and history"

  if ! homeDir=$(sudo getent passwd "${user}" | cut -d: -f6)
  then
    echo "No such user '${user}', skipping" >&2
    continue
  fi

  if [ -z "${homeDir}" ]
  then
    echo "Could not determine home directory for '${user}', skipping" >&2
    continue
  fi

  for dir in .ssh .local
  do
    sudo rm -rf ${homeDir}/${dir}
  done

  for file in anaconda-ks.cfg .lesshst .bash_history .zsh_history .viminfo .python_history
  do
    sudo rm -f ${homeDir}/${file}
  done
done

# Setup authorized key login
sudo rm -rf /home/${defaultUser}/.ssh
mkdir -p /home/${defaultUser}/.ssh
chown ${defaultUser}:${defaultUser} /home/${defaultUser}/.ssh
chmod 700 /home/${defaultUser}/.ssh
cat <<EOF >/home/${defaultUser}/.ssh/authorized_keys
${authorizedKey}
EOF

# Setup authorized key login for the ansible automation user - its .ssh was wiped by the
# "Cleaning up users" loop above just like ${defaultUser}'s, but unlike ${defaultUser} it has
# no other step in this pipeline that restores it, so it must be reinstalled here too.
sudo mkdir -p /home/${ansibleUser}/.ssh
sudo chown ${ansibleUser}:${ansibleUser} /home/${ansibleUser}/.ssh
sudo chmod 700 /home/${ansibleUser}/.ssh
sudo tee /home/${ansibleUser}/.ssh/authorized_keys >/dev/null << EOF
${ansibleAuthorizedKey}
EOF
sudo chown ${ansibleUser}:${ansibleUser} /home/${ansibleUser}/.ssh/authorized_keys
sudo chmod 600 /home/${ansibleUser}/.ssh/authorized_keys

echo "Removing logs"
sudo find /var/log/ -type f -exec rm -f {} \;

echo "Removing DHCP leases"
sudo rm -f /var/lib/dhcp/*

echo "Removing systemd random seed"
sudo rm -f /var/lib/systemd/random-seed

read -p "Press any key to shutdown..." -n 1 -r

echo "Shutting down"
sudo /usr/sbin/shutdown now
