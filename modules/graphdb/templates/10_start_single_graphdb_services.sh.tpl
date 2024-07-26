#!/bin/bash

# This script focuses on starting GraphDB service and setting up the security in a single node deployment.
#
# It performs the following tasks:
#   * Retrieves essential metadata about the Azure instance, including the instance ID, RG, DNS zone name, and GraphDB password.
#   * Initiates GraphDB
#   * Changes the admin user password and enables security if not already enabled.
#   * Updates the GraphDB admin password if it has been changed in Application Config

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

echo "###########################"
echo "#    Starting GraphDB     #"
echo "###########################"

RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
DNS_ZONE_NAME=${private_dns_zone_name}
GRAPHDB_ADMIN_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
GRAPHDB_PASSWORD_CREATION_TIME="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .lastModified)"

# To update the password if changed we need to save the creation date of the config.
# If a file is found, it will treat the password from Application config as the latest and update it.
if [ ! -e "/var/opt/graphdb/password_creation_time" ]; then
  # This has to be persisted
  echo $(date -d "$GRAPHDB_PASSWORD_CREATION_TIME" -u +"%Y-%m-%dT%H:%M:%S") >/var/opt/graphdb/password_creation_time
  GRAPHDB_PASSWORD=$GRAPHDB_ADMIN_PASSWORD
else
  # Gets the previous password
  PASSWORD_CREATION_DATE=$(cat /var/opt/graphdb/password_creation_time)
  GRAPHDB_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password --datetime $PASSWORD_CREATION_DATE | jq -r .value | base64 -d)"
fi

RETRY_DELAY=5

systemctl daemon-reload
systemctl start graphdb

log_with_timestamp "Started GraphDB services"

check_status() {
  STATUS=$(curl -s -o /dev/null -w "%%{http_code}" "http://localhost:7200/rest/cluster/node/status")
  if [[ $STATUS -eq 200 || $STATUS -eq 404 ]]; then
    return 0
  else
    return 1
  fi
}

# Wait for the status code to be 200 or 404
until check_status; do
  sleep 5
done

echo "###########################################################"
echo "#    Changing admin user password and enable security     #"
echo "###########################################################"

configure_graphdb_security "$GRAPHDB_ADMIN_PASSWORD"

echo "####################################"
echo "#    Updating GraphDB password     #"
echo "####################################"

update_graphdb_admin_password_single_node "$GRAPHDB_PASSWORD" "$GRAPHDB_ADMIN_PASSWORD" "$RETRY_DELAY" "${app_configuration_endpoint}"

echo "###########################"
echo "#    Script completed     #"
echo "###########################"
