#!/bin/bash
#
# Regenerates per-host secrets (SSH host keys, systemd random seed) on a VM
# that was already cloned/configured before config.sh correctly rotated the
# SSH host keys (previously "ssh-keygen -A" was a silent no-op because the
# keys were already baked into the template disk, so every clone shared the
# same host keys and, potentially, the same random seed).
#
# Safe to run on an already-configured, in-service VM:
#   - Existing SSH sessions are unaffected.
#   - New SSH connections will see a host key mismatch until clients refresh
#     their known_hosts (instructions are printed at the end).
#   - The machine-id is NOT touched, it was already unique per clone.
#
set -euo pipefail

assumeYes=false
if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]
then
  assumeYes=true
fi

if [ ${EUID} -ne 0 ]
then
  echo "You must run as root" >&2
  exit 1
fi

echo "Host: $(hostname)"
echo "machine-id: $(cat /etc/machine-id 2>/dev/null || echo unknown) (not touched by this script, should already be unique per VM)"

if [ "${assumeYes}" != "true" ]
then
  read -p "Regenerate SSH host keys and random seed on this host? (y/N): " -n 1 -r
  echo ""
  if ! [[ ${REPLY} =~ ^[Yy]$ ]]
  then
    echo "Aborted"
    exit 1
  fi
fi

echo "Regenerating SSH host keys"
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

echo "Restarting sshd to pick up the new host keys"
if ! systemctl restart ssh 2>/dev/null && ! systemctl restart sshd 2>/dev/null
then
  echo "Could not restart the ssh service automatically, restart it manually" >&2
fi

echo "Reinitializing the systemd random seed"
rm -f /var/lib/systemd/random-seed
if ! systemctl restart systemd-random-seed.service 2>/dev/null
then
  echo "Could not restart systemd-random-seed.service (may not exist on this system) - a fresh seed will still be written at next shutdown" >&2
fi

cat <<EOF

Done. New host key fingerprints for $(hostname):
EOF
for key in /etc/ssh/ssh_host_*.pub
do
  ssh-keygen -lf "${key}"
done

cat <<EOF

IMPORTANT: any client that previously connected to this host (SSH clients,
Ansible, etc.) will now see a HOST KEY MISMATCH warning. Refresh their
known_hosts, e.g.:
  ssh-keygen -R <hostname-or-ip>
  ssh-keyscan <hostname-or-ip> >> ~/.ssh/known_hosts
EOF
