#!/bin/bash

# This script focuses on configuring Telegraf service.
#
# It performs the following tasks:
#   * Retrieves the instance's resource ID and region ID from Azure Metadata service.
#   * Fetches the GraphDB admin password from Azure App Configuration, decodes it from base64, and assigns it to the GRAPHDB_ADMIN_PASSWORD variable.
#   * Overrides the configuration file for Telegraf.
#   * Restarts the Telegraf service to apply the updated configuration.

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

echo "###############################"
echo "#    Configuring Telegraf     #"
echo "###############################"

RESOURCE_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text")
REGION_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-01-01&format=text")
GRAPHDB_ADMIN_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"

# Overrides the config file
cat <<-EOF >/etc/telegraf/telegraf.conf
  [[inputs.prometheus]]
    urls = ["http://localhost:7200/rest/monitor/infrastructure", "http://localhost:7200/rest/monitor/structures"]
    username = "admin"
    password = "$${GRAPHDB_ADMIN_PASSWORD}"

  [[outputs.azure_monitor]]
    namespace_prefix = "Telegraf/"
    region = "$REGION_ID"
    resource_id = "$RESOURCE_ID"
EOF
# Prevent any other user (except root) from reading the telegraf config. Apply recursively for entire dir
chmod -R og-rwx /etc/telegraf

systemctl restart telegraf

log_with_timestamp "Completed configuring Telegraf"
