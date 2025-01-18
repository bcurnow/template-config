#!/bin/bash
#
# Reconfigures the VM to be a proxmox template
#
cat <<EOF
Please ensure the following commands are run as the non-root user before executing:

  set +o history # Turns off history for the current shell
  history -c     # Clears current history

This will ensure there's no extraneous command history when the template is cloned
EOF
read -p "Press any key to continue..." -n 1 -r

echo "Ensuring hostname is 'debian-template'"
echo "debian-template" | sudo tee /etc/hostname >/dev/null

echo "Updating /etc/hosts"
sudo tee /etc/hosts >/dev/null << EOF
127.0.0.1	localhost
127.0.0.1	debian-template.internal.curnowtopia.com	debian-template
EOF

echo "Clearing the machine id"
sudo rm -f /etc/machine-id

echo "Removing systemd-networkd configurations"
sudo rm /etc/systemd/network/*.network

echo "Setting up template systemd-networkd configuration"
sudo tee /etc/systemd/network/template.network >/dev/null << EOF
[Match]
Name=ens18

[Network]
# Do not provision an ipv6 address
IPv6LinkLocalAddressGenerationMode=none
Address=10.2.2.224/24
DNS=10.0.0.3
DNS=10.0.0.4
Domains=internal.curnowtopia.com

[Route]
Gateway=10.2.2.1
EOF

echo "Generating a new SSH keys"
sudo rm -f /etc/ssh/ssh_host_*
sudo ssh-keygen -A

echo "Clearing bcurnow user configuration and history"
rm -rf /home/bcurnow/.ssh/
rm -f /home/bcurnow/anaconda-ks.cfg
rm -f /home/bcurnow/bash_history
rm -f /home/bcurnow/lesshst
rm -rf /home/bcurnow/local

# Setup authorized key login for my public key
mkdir -p /home/bcurnow/ssh
chmod 700 /home/bcurnow/ssh
cat <<EOF >/home/bcurnow/ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJMQ7gGnSRqhGbeiFm3MAfJ2DzJc3UMPBazhZIoXYLbKXaUFKPV2YuvTDeaXEa1UiAoxQJmhq94ABc2kPBfdfPSVd0elOKiKBbdpwO5PrKxK3DpxdX46GgKp0kRW8a3UgAUOuo0nigaEd7pWlkJ8+zxR0aFzfpbRiqIHTT8L3gVsRiQIrs0vkwn7sUMQs7ODJGz2bBuL6aI5aPyiyxoMlLfeo7AabnBIXCM5Bfym6m0/KmUkSugWyOgKXMCscBNiclC3QO/ExjouKnrlXQg9f/+I2J3FAex/QRRl1m7G1NPYygd1NIVcoNCIrU4g5aZkKqCk0DZC08mKVZ2zuRtqaluGMEfYd6LMGXSjuaFYDmtybvwEgvSlT9fkDCZcwF65YBnHXdr/QNWG4D5U3tXh5o4H202o6rsdsVhIsKIAkFqiiiC3yeCWiDVR2wQNENNkMbL/7tZMSqRm31iJjvQNuCBPpu6Z59DNkmZqb8dDgrOyi8SREBKf7FLuKx/jp7R4k= Brian.Curnow@T07M6PT2TT
EOF

echo "Clearing root configuration and history"
sudo rm -rf /root/.ssh/
sudo rm -f /root/anaconda-ks.cfg
sudo rm -f /root/.bash_history
sudo rm -f /root/.lesshst
sudo rm -rf /root/.local

echo "Clearing ansible configuration and history"
sudo rm -f /home/ansible/.ssh/known_hosts
sudo rm -f /home/ansible/anaconda-ks.cfg
sudo rm -f /home/ansible/.bash_history
sudo rm -f /home/ansible/.lesshst
sudo rm -rf /home/ansible/.local

echo "Clearing apt caches"
sudo apt-get autoremove -y
sudo apt-get clean -y
sudo apt-get autoclean -y

echo "Removing logs"
sudo find /var/log/ -type f -exec rm -f {} \;

read -p "Press any key to shutdown..." -n 1 -r

echo "Shutting down"
sudo /usr/sbin/shutdown now
