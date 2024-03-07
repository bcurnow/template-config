#!/bin/bash
#
# Downloads the lastest version of the template-config scripts
#

if [ ${EUID} -eq 0 ]
then
  echo "This must not be run as root" >&2
  exit 1
fi

echo "Clearing /opt/template-config"
sudo rm -rf /opt/template-config
sudo mkdir -p /opt/template-config

echo "Downloading lastest version of the template-config scripts"
sudo curl --silent -o /opt/template-config/make-template.sh --location  https://github.com/bcurnow/utils/raw/main/template-config/make-template.sh
if [ $? -ne 0 ]
then
  echo "Download of make-template.sh failed" >&2
  exit 1
fi
sudo chmod 755 /opt/template-config/make-template.sh
sudo curl --silent -o /opt/template-config/config-template.sh --location  https://github.com/bcurnow/utils/raw/main/template-config/config-template.sh
if [ $? -ne 0 ]
then
  echo "Download of config-template.sh failed" >&2
  exit 1
fi
sudo chmod 755 /opt/template-config/config-template.sh
