#!/bin/bash
#
# Downloads the lastest version of the template-config scripts
#

if [ ${EUID} -ne 0 ]
then
  echo "This must be run as root" >&2
  exit 1
fi

echo "Clearing /opt/template-config"
rm -rf /opt/template-config
mkdir -p /opt/template-config

echo "Downloading lastest version of the template-config scripts"
for script in "make-template.sh config-template.sh template-download.sh"
do
curl --silent -o /opt/template-config/${script} --location https://github.com/bcurnow/template-config/raw/main/template-config/${script}
if [ $? -ne 0 ]
then
  echo "Download of ${script} failed" >&2
  exit 1
fi
chmod 755 /opt/template-config/${script}
done
