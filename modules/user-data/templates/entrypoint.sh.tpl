#!/usr/bin/env bash

set -euxo pipefail

# Login in Azure CLI with managed identity (user or system assigned)
az login --identity

echo "Configuring GraphDB instance"

# Stop in order to override configurations
systemctl stop graphdb

# Set keepalive and file max size
echo 'net.ipv4.tcp_keepalive_time = 120' | tee -a /etc/sysctl.conf
echo 'fs.file-max = 262144' | tee -a /etc/sysctl.conf

sysctl -p

#TODO check for VMSS instance in stopped state and remove it if present (stopped, failed)


