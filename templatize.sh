#!/bin/bash
#
# Reconfigures the VM to be a proxmox template
#
defaultUser=bcurnow
authorizedKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJMQ7gGnSRqhGbeiFm3MAfJ2DzJc3UMPBazhZIoXYLbKXaUFKPV2YuvTDeaXEa1UiAoxQJmhq94ABc2kPBfdfPSVd0elOKiKBbdpwO5PrKxK3DpxdX46GgKp0kRW8a3UgAUOuo0nigaEd7pWlkJ8+zxR0aFzfpbRiqIHTT8L3gVsRiQIrs0vkwn7sUMQs7ODJGz2bBuL6aI5aPyiyxoMlLfeo7AabnBIXCM5Bfym6m0/KmUkSugWyOgKXMCscBNiclC3QO/ExjouKnrlXQg9f/+I2J3FAex/QRRl1m7G1NPYygd1NIVcoNCIrU4g5aZkKqCk0DZC08mKVZ2zuRtqaluGMEfYd6LMGXSjuaFYDmtybvwEgvSlT9fkDCZcwF65YBnHXdr/QNWG4D5U3tXh5o4H202o6rsdsVhIsKIAkFqiiiC3yeCWiDVR2wQNENNkMbL/7tZMSqRm31iJjvQNuCBPpu6Z59DNkmZqb8dDgrOyi8SREBKf7FLuKx/jp7R4k= Brian.Curnow@T07M6PT2TT"

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

echo "Clearing apt caches"
sudo apt-get autoremove -y
sudo apt-get clean -y
sudo apt-get autoclean -y

echo "Cleaning up users"
for user in ${defaultUser} ansible root
do
  echo "Clearing ${user} configuration and history"
  homeDir=$(echo ~${user})

  for dir in .ssh .local
  do
    rm -rf ${homeDir}/${dir}
  done

  for file in anaconda-ks.cfg .lesshst .bash_history
  do
    rm -f ${homeDir}/${file}
  done
done

# Setup authorized key login
mkdir -p /home/${defaultUser}/ssh
chown ${defaultUser}:${defaultUser} /home/${defaultUser}/ssh
chmod 700 /home/${defaultUser}/ssh
cat <<EOF >/home/${defaultUser}/ssh/authorized_keys
${authorizedKey}
EOF

echo "Removing logs"
sudo find /var/log/ -type f -exec rm -f {} \;

read -p "Press any key to shutdown..." -n 1 -r

echo "Shutting down"
sudo /usr/sbin/shutdown now
