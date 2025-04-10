#!/bin/bash

# This script focuses on the GraphDB cluster creation and enabling the security.
#
# It performs the following tasks:
#   * Retrieves essential metadata about the Azure instance, including the instance ID, RG, DNS zone name, and GraphDB password.
#   * Initiates GraphDB and enables the GraphDB cluster proxy service.
#   * Monitors the availability of GraphDB instances using DNS records and waits for all instances to be running.
#   * Finds the instance with lowest ID in the VMSS.
#     * If the current instance has the lowest ID, it attempts to create a GraphDB cluster, retries if necessary, and confirms the cluster's existence.
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

INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
DNS_ZONE_NAME=${private_dns_zone_name}
GRAPHDB_ADMIN_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
GRAPHDB_PASSWORD_CREATION_TIME="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .lastModified)"
VMSS_NAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-01-01&format=text")
GRAPHDB_NODE_COUNT="$(az appconfig kv show \
  --endpoint ${app_configuration_endpoint} \
  --auth-mode login \
  --key node_count \
  | jq -r .value)"

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

MAX_RETRIES=3
RETRY_DELAY=5

systemctl daemon-reload
systemctl start graphdb
systemctl enable graphdb-cluster-proxy.service
systemctl start graphdb-cluster-proxy.service

log_with_timestamp "Started GraphDB services"

check_gdb() {
  if [ -z "$1" ]; then
    log_with_timestamp "Error: IP address or hostname is not provided."
    return 1
  fi

  local gdb_address="$1:7200/rest/monitor/infrastructure"
  if curl -s --head -u "admin:$${GRAPHDB_PASSWORD}" --fail "$gdb_address" >/dev/null; then
    log_with_timestamp "Success, GraphDB node $gdb_address is available"
    return 0
  else
    log_with_timestamp "GraphDB node $gdb_address is not available yet"
    return 1
  fi
}

# Function to check if the GraphDB license has been applied
check_license() {
  # Define the URL to check
  local URL="http://localhost:7200/rest/graphdb-settings/license"

  # Send an HTTP GET request and store the response in a variable
  local response=$(curl -s "$URL")

  # Check if the response contains the word "free"
  if [[ "$response" == *"free"* ]]; then
    log_with_timestamp "Free license detected"
    exit 1
  fi
}
# Get all instance IDs for the current VMSS
INSTANCE_IDS=($(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[].instanceId" --output tsv))
# Sort instance IDs
SORTED_INSTANCE_IDS=($(echo "$${INSTANCE_IDS[@]}" | tr ' ' '\n' | sort -n))
# Find the lowest ID
LOWEST_INSTANCE_ID=$${SORTED_INSTANCE_IDS[0]}

#  Only the instance with the lowest ID would attempt to create the cluster
if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then

  echo "##################################"
  echo "#    Beginning cluster setup     #"
  echo "##################################"

  wait_dns_records "$DNS_ZONE_NAME" "$RESOURCE_GROUP" "$GRAPHDB_NODE_COUNT"
  check_all_dns_records "$DNS_ZONE_NAME" "$RESOURCE_GROUP" "$RETRY_DELAY"

  for ((i = 1; i <= $MAX_RETRIES; i++)); do
    IS_CLUSTER=$(
      curl -s -o /dev/null \
        -u "admin:$GRAPHDB_PASSWORD" \
        -w "%%{http_code}" \
        http://localhost:7200/rest/monitor/cluster
    )

    # 000 = no HTTP code was received
    if [[ "$IS_CLUSTER" == 000 ]]; then
      log_with_timestamp "Retrying ($i/$MAX_RETRIES) after $RETRY_DELAY seconds..."
      sleep $RETRY_DELAY
    elif [ "$IS_CLUSTER" == 503 ]; then
      EXISTING_DNS_RECORDS=$(az network private-dns record-set list -g $RESOURCE_GROUP -z $DNS_ZONE_NAME --query "[?starts_with(name, 'node')].fqdn")
      CLUSTER_ADDRESS_GRPC=$(echo "$EXISTING_DNS_RECORDS" | jq -r '[ .[] | rtrimstr(".") + ":7300" ]')
      CLUSTER_CREATED=$(
        curl -X POST -s http://node-1.$DNS_ZONE_NAME:7200/rest/cluster/config \
          -w "%%{http_code}" \
          -o "/dev/null" \
          -H 'Content-type: application/json' \
          -u "admin:$${GRAPHDB_PASSWORD}" \
          -d "{\"nodes\": $CLUSTER_ADDRESS_GRPC}"
      )

      if [[ "$CLUSTER_CREATED" == 201 ]]; then
        log_with_timestamp "GraphDB cluster successfully created!"
        break
      else
        log_with_timestamp "Unexpected Status code returned $CLUSTER_CREATED"
      fi
    elif [ "$IS_CLUSTER" == 200 ]; then
      log_with_timestamp "Cluster exists"
      break
    else
      log_with_timestamp "Something went wrong, returned: $IS_CLUSTER. Check the logs!"
    fi
  done

  # Setting the security should be done on the Leader node only
  echo "###########################################################"
  echo "#    Changing admin user password and enable security     #"
  echo "###########################################################"

  configure_graphdb_security "$GRAPHDB_ADMIN_PASSWORD"
else
  log_with_timestamp "The current instance: $INSTANCE_ID is not the lowest, skipping cluster creation"
fi

echo "####################################"
echo "#    Updating GraphDB password     #"
echo "####################################"

# This will update the GraphDB admin password if this node has the lowest ID and password_creation_time file exists.
if [[ -e "/var/opt/graphdb/password_creation_time" && "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]]; then
  update_graphdb_admin_password "$GRAPHDB_PASSWORD" "$GRAPHDB_ADMIN_PASSWORD" "$RETRY_DELAY" "${app_configuration_endpoint}" "$${ALL_DNS_RECORDS[@]}"
else
  log_with_timestamp "The current instance: $INSTANCE_ID is not the lowest, skipping password update"
fi
