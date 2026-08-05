#!/bin/bash
#
# Reconfigures the VM to be a proxmox template
#
set -euo pipefail

defaultUser=bcurnow
authorizedKey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJMQ7gGnSRqhGbeiFm3MAfJ2DzJc3UMPBazhZIoXYLbKXaUFKPV2YuvTDeaXEa1UiAoxQJmhq94ABc2kPBfdfPSVd0elOKiKBbdpwO5PrKxK3DpxdX46GgKp0kRW8a3UgAUOuo0nigaEd7pWlkJ8+zxR0aFzfpbRiqIHTT8L3gVsRiQIrs0vkwn7sUMQs7ODJGz2bBuL6aI5aPyiyxoMlLfeo7AabnBIXCM5Bfym6m0/KmUkSugWyOgKXMCscBNiclC3QO/ExjouKnrlXQg9f/+I2J3FAex/QRRl1m7G1NPYygd1NIVcoNCIrU4g5aZkKqCk0DZC08mKVZ2zuRtqaluGMEfYd6LMGXSjuaFYDmtybvwEgvSlT9fkDCZcwF65YBnHXdr/QNWG4D5U3tXh5o4H202o6rsdsVhIsKIAkFqiiiC3yeCWiDVR2wQNENNkMbL/7tZMSqRm31iJjvQNuCBPpu6Z59DNkmZqb8dDgrOyi8SREBKf7FLuKx/jp7R4k= Brian.Curnow@T07M6PT2TT"

# The following network settings reflect my own network. If you're using this script outside of
# it, change these values to match your own network before running it.
templateIp=10.2.2.224
templatePrefix=24
templateGateway=10.2.2.1
dnsServer1=10.0.0.3
dnsServer2=10.0.0.4
domain=internal.curnowtopia.com
vlan=12
# DNS servers live on VLAN 1 on my network, regardless of which VLAN a given host is on
dnsVlan=1
# This is a ULA (Unique Local Address, RFC 4193) prefix that's private to my network - do not
# reuse this one, generate your own instead (e.g. https://www.unique-local-ipv6.com/)
ulaPrefix=fdc1:e344:ba0a

# Our IPv6 addressing convention encodes the IPv4 address directly into the host
# part of the address, e.g. 10.2.2.100 on VLAN 12 with ULA prefix fdc1:e344:ba0a
# becomes fdc1:e344:ba0a:12:10:2:2:100
ipv6_encode () {
  local prefix=$1
  local ipv4=$2
  local vlan=$3

  echo "${prefix}:${vlan}:${ipv4//./:}"
}

templateIpv6=$(ipv6_encode "${ulaPrefix}" "${templateIp}" "${vlan}")
templateGatewayIpv6=$(ipv6_encode "${ulaPrefix}" "${templateGateway}" "${vlan}")
dnsServer1Ipv6=$(ipv6_encode "${ulaPrefix}" "${dnsServer1}" "${dnsVlan}")
dnsServer2Ipv6=$(ipv6_encode "${ulaPrefix}" "${dnsServer2}" "${dnsVlan}")

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
127.0.0.1	debian-template.${domain}	debian-template
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
Address=${templateIpv6}/64
DNS=${dnsServer1}
DNS=${dnsServer1Ipv6}
DNS=${dnsServer2}
DNS=${dnsServer2Ipv6}
Domains=${domain}
Gateway=${templateGateway}
Gateway=${templateGatewayIpv6}

# The template has no machine-id (cleared below), which breaks the DHCPv6 client's ability to
# generate a DUID. The router advertises a GUA prefix, so accepting RAs here would trigger DHCPv6
# and fail. The static addresses above are all this VM needs before it's shut down and templated,
# so just don't accept RAs at all.
IPv6AcceptRA=no
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

echo "Removing logs"
sudo find /var/log/ -type f -exec rm -f {} \;

echo "Removing DHCP leases"
sudo rm -f /var/lib/dhcp/*

echo "Removing systemd random seed"
sudo rm -f /var/lib/systemd/random-seed

read -p "Press any key to shutdown..." -n 1 -r

echo "Shutting down"
sudo /usr/sbin/shutdown now
