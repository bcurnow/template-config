#!/bin/bash
#
# To be run after cloning a VM that was prepared with templatize.sh
#
set -euo pipefail

prompt () {
  local prompt=$1
  local result_name=$2
  local validation_function=${3:-}
  local default_value=${4:-}

  if [ -z "${prompt}" ]
  then
    echo "You must provide a prompt" >&2
    return 1
  fi

  if [ -z "${validation_function}" ]
  then
    validation_function=check_yes
  fi

  if [ -z "${result_name}" ]
  then
    echo "You must provide a result variable name" >&2
    return 1
  fi

  if [ -n "${default_value}" ]
  then
    prompt="${prompt} [${default_value}]"
  fi

  # Make the result variable a nameref this means we'll write the result to a variable that the caller can view
  local -n result_var="${result_name}"

  while true
  do
    read -p "${prompt}: " ${result_name}

    if [ -z "${result_var:-}" ]
    then
      if [ -n "${default_value}" ]
      then
        printf -v "${result_name}" "%s" "${default_value}"
      fi
    fi

    if [ -n "${result_var:-}" ]
    then
      if ! $(${validation_function} "${result_var}")
      then
        unset "${result_name}"
      fi
    fi
    [ -z "${result_var:-}" ] || break
  done
}

confirm () {
  local prompt=$1

  if [ -z "${prompt}" ]
  then
    echo "You must provide a prompt" >&2
    return 1
  fi

  read -p "${prompt} (Y/n): " -n 1 -r
  echo ""
  [[ -z "${REPLY}" || ${REPLY} =~ ^[Yy]$ ]]
}

function check_yes () {
  return 0
}

check_numeric () {
  local type=$1
  local nbr=$2
  local -i min=${3:-0}
  local -i max=${4:-255}
  local quiet=${5:-}

  if [ -z "${type}" ]
  then
    echo "You must provide a type" >&2
  fi

  if [ -z "${nbr}" ]
  then
    echo "${type} must have a value" >&2
    return 1
  fi

  if [ -z "${quiet}" ]
  then
    quiet=true
  fi

  if ! [[ "${nbr}" =~ ^-?[0-9]+$ ]]
  then
    echo "Invalid ${type} '${nbr}', must be numeric" >&2
    return 1
  fi

  if [ "${nbr}" -lt "${min}" ] || [ "${nbr}" -gt "${max}" ]
  then
    echo "Invalid ${type} '${nbr}', must be in the range ${min}-${max}" >&2
    return 1
  fi

  return 0
}

check_ip_addr () {
  local ip=$1

  if [ -z "${ip}" ]
  then
    echo "You must provide an IP address to check" >&2
    return 1
  fi

  local octets=($(echo "${ip}" | tr "." " "))

  if [ "${#octets[@]}" -lt 4 ] || [ "${#octets[@]}" -gt 4 ]
  then
    echo "Wrong number of octets, expected 4 but got ${#octets[@]}" >&2
    return 1
  fi

  local min=0
  for i in "${!octets[@]}"
  do
    if [ ${i} -eq 0 ]
    then
      min=1
    else
       min=0
    fi

    if ! check_numeric "IP octet" "${octets[i]}" ${min} 255 false
    then
      return 1
    fi
  done

  return 0
}

check_ip_prefix () {
  local -i prefix=$1

  if check_numeric "prefix" ${prefix} 1 32
  then
    return 0
  fi

  return 1
}

check_vlan () {
  local -i vlan=$1

  if check_numeric "VLAN tag" ${vlan} 1 4094
  then
    return 0
  fi

  return 1
}

check_ula_prefix () {
  local prefix=$1

  if [ -z "${prefix}" ]
  then
    echo "You must provide a ULA prefix" >&2
    return 1
  fi

  if ! [[ "${prefix}" =~ ^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}$ ]]
  then
    echo "Invalid ULA prefix '${prefix}', expected 3 colon-separated hex groups (e.g. fdc1:e344:ba0a)" >&2
    return 1
  fi

  return 0
}

# Our IPv6 addressing convention encodes the IPv4 address directly into the host
# part of the address, e.g. 10.2.12.100 on VLAN 12 with ULA prefix fdc1:e344:ba0a
# becomes fdc1:e344:ba0a:12:10:2:12:100
ipv6_encode () {
  local prefix=$1
  local ipv4=$2
  local vlan=$3

  echo "${prefix}:${vlan}:${ipv4//./:}"
}

if [ ${EUID} -ne 0 ]
then
  echo "You must run as root" >&2
  exit 1
fi

# The following defaults reflect my own network. If you're using this script outside of it,
# change these values (or override them at the prompts below) to match your own network.
dns_server1=10.2.5.10
dns_server2=10.2.5.11
gateway=10.2.12.1
domain=internal.curnowtopia.com
# DNS servers live on the Infra Services VLAN (5) on my network, regardless of which VLAN a
# given host is on
dns_vlan=5
# This is a ULA (Unique Local Address, RFC 4193) prefix that's private to my network - do not
# reuse this one, generate your own instead (e.g. https://www.unique-local-ipv6.com/)
ula_prefix=fdc1:e344:ba0a

prompt "Enter the new hostname" hostname
prompt "Enter the new IP address" ip_addr check_ip_addr
prompt "Enter the IP prefix length" ip_prefix check_ip_prefix "24"
prompt "Enter the VLAN tag for this network" vlan check_vlan
prompt "Enter the IPv6 ULA prefix" ula_prefix check_ula_prefix "${ula_prefix}"
prompt "Enter the gatway address" gateway check_ip_addr "${gateway}"
prompt "Enter the DNS search domain" domain check_yes "${domain}"

dns_over_tls=yes
if ! confirm "Use DNS-over-TLS for the DNS servers below?"
then
  dns_over_tls=no
fi

prompt "Enter the first DNS server" dns_server1 check_ip_addr "${dns_server1}"
if [ "${dns_over_tls}" = "yes" ]
then
  prompt "Enter the first DNS server's hostname (used to validate its TLS certificate)" dns_server1_hostname check_yes "ns1.${domain}"
fi

prompt "Enter the second DNS server" dns_server2 check_ip_addr "${dns_server2}"
if [ "${dns_over_tls}" = "yes" ]
then
  prompt "Enter the second DNS server's hostname (used to validate its TLS certificate)" dns_server2_hostname check_yes "ns2.${domain}"
fi

ipv6_addr=$(ipv6_encode "${ula_prefix}" "${ip_addr}" "${vlan}")
dns_server1_v6=$(ipv6_encode "${ula_prefix}" "${dns_server1}" "${dns_vlan}")
dns_server2_v6=$(ipv6_encode "${ula_prefix}" "${dns_server2}" "${dns_vlan}")

if [ "${dns_over_tls}" = "yes" ]
then
  dns_lines="DNS=${dns_server1}#${dns_server1_hostname}
DNS=${dns_server1_v6}#${dns_server1_hostname}
DNS=${dns_server2}#${dns_server2_hostname}
DNS=${dns_server2_v6}#${dns_server2_hostname}"
  dns_over_tls_line="DNSOverTLS=yes"
else
  dns_lines="DNS=${dns_server1}
DNS=${dns_server1_v6}
DNS=${dns_server2}
DNS=${dns_server2_v6}"
  dns_over_tls_line=""
fi

cat <<EOF
---------------------------------------------------------------------------
New VM Config:
  IP Address: ${ip_addr}/${ip_prefix}
  IPv6 Address: ${ipv6_addr}/64
  VLAN: ${vlan}
  IPv6 ULA Prefix: ${ula_prefix}
  Gateway: ${gateway}
  Hostname: ${hostname}
  DNS Servers:
    ${dns_server1} / ${dns_server1_v6}
    ${dns_server2} / ${dns_server2_v6}
  DNS Search Domain: ${domain}
  DNS-over-TLS: ${dns_over_tls}
---------------------------------------------------------------------------
EOF
if ! confirm "Is the above correct?"
then
  exit 1
fi

echo "Removing existing network config"
rm -f /etc/systemd/network/*.network

echo "Creating network config for ens18"
cat <<EOF > /etc/systemd/network/10-ens18.network
[Match]
Name=ens18

[Network]
Address=${ip_addr}/${ip_prefix}
Address=${ipv6_addr}/64
${dns_lines}
Domains=${domain}
Gateway=${gateway}
${dns_over_tls_line}
EOF

echo "Updating hostname"
echo "${hostname}" > /etc/hostname

echo "Updating /etc/hosts"
cat <<EOF > /etc/hosts
127.0.0.1	${hostname}.${domain} ${hostname} localhost # managed by ansible
EOF

echo "Regenerating /etc/machine-id"
/usr/bin/systemd-machine-id-setup

echo "Regenerating SSH host keys"
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

cat <<EOF
Cleaning out /opt/template-config
If you need to re-run anything, use push-scripts.sh from your workstation (e.g.
./push-scripts.sh ${hostname}) instead of redownloading them here - this VM isn't guaranteed to
have curl (or any other network client) installed.
EOF

read -p "Press any key to reboot..." -n 1 -r

# We have configured this VM, we can remove template-config
rm -rf /opt/template-config
reboot now
