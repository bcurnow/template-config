#!/bin/bash
#
# Copies the current templatize.sh and config.sh from this checkout onto a target VM's
# /opt/template-config, for updating an already-built debian-template VM without rebuilding it.
#
# Run this from your workstation, against the VM over SSH - it's not meant to run on the VM
# itself, and (like regenerate-secrets.sh) is not part of the golden template: it's not fetched
# by build-debian-template.sh, so it never ends up on a template or a clone.
#
# Usage: push-scripts.sh [host]   (defaults to debian-template)
#
set -euo pipefail

host=${1:-debian-template}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "Clearing any existing scripts on ${host}"
ssh "${host}" 'sudo mkdir -p /opt/template-config && sudo rm -f /opt/template-config/*.sh && sudo chown "$(id -un)" /opt/template-config'

echo "Copying templatize.sh and config.sh to ${host}:/opt/template-config"
scp "${script_dir}/templatize.sh" "${script_dir}/config.sh" "${host}:/opt/template-config/"

echo "Fixing ownership and permissions"
ssh "${host}" 'sudo chown root:root /opt/template-config /opt/template-config/*.sh && sudo chmod 755 /opt/template-config/*.sh'

echo "Done"
