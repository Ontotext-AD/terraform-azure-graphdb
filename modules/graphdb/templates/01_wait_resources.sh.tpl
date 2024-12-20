#!/usr/bin/env bash

# This scripts wait for resources on which the VM relies to exists and with access to
# Because Terraform creates resources in parallel, the VM could try to access a resources that is still being created in Azure in the background

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")

POLL_INTERVAL=5
MAX_TIMEOUT=600

# Provided by Terraform
PRIVATE_DNS_ZONE_NAME="${private_dns_zone_name}"
PRIVATE_DNS_ZONE_ID="${private_dns_zone_id}"
PRIVATE_DNS_ZONE_LINK_NAME="${private_dns_zone_link_name}"
PRIVATE_DNS_ZONE_LINK_ID="${private_dns_zone_link_id}"
APP_CONFIGURATION_ENDPOINT="${app_configuration_endpoint}"
APP_CONFIGURATION_ID="${app_configuration_id}"
STORAGE_ACCOUNT_NAME=${storage_account_name}
GRAPHDB_NODE_COUNT=${node_count}
VMSS_NAME=${vmss_name}
RESOURCE_GROUP=${resource_group}

# Only run the wait_vmss_nodes function if graphdb_node_count is more than 1
if [ "$GRAPHDB_NODE_COUNT" -gt 1 ]; then
echo "GraphDB node count is greater than 1. Running wait_vmss_nodes..."
wait_for_vmss_nodes "$VMSS_NAME" "$RESOURCE_GROUP"
else
echo "GraphDB node count is not greater than 1. Skipping wait_vmss_nodes."
fi

waitForAppConfigKey() {
  local config_key="$1"

  local start_time=$(date +%s)
  while true; do
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - start_time))

    if az appconfig kv show --endpoint "$APP_CONFIGURATION_ENDPOINT" --auth-mode login --key "$config_key" &>/dev/null; then
      log_with_timestamp "Configuration '$config_key' in App Configuration '$APP_CONFIGURATION_ENDPOINT' is available."
      return 0 # Success
    elif [ "$elapsed_time" -ge "$MAX_TIMEOUT" ]; then
      log_with_timestamp "Timeout reached. Configuration did not become available in time."
      return 1 # Timeout
    else
      log_with_timestamp "Configuration is still being created. Waiting for $POLL_INTERVAL seconds..."
      sleep "$POLL_INTERVAL"
    fi
  done
}

log_with_timestamp "Waiting for Private DNS zone: $PRIVATE_DNS_ZONE_NAME"
time az resource wait \
  --resource-group "$RESOURCE_GROUP" \
  --ids "$PRIVATE_DNS_ZONE_ID" \
  --namespace "Microsoft.Network" \
  --resource-type "privateDnsZones" \
  --created \
  --interval $POLL_INTERVAL \
  --timeout $MAX_TIMEOUT

log_with_timestamp "Waiting for Private DNS zone link: $PRIVATE_DNS_ZONE_LINK_NAME"
time az resource wait \
  --resource-group "$RESOURCE_GROUP" \
  --ids "$PRIVATE_DNS_ZONE_LINK_ID" \
  --namespace "Microsoft.Network" \
  --resource-type "privateDnsZones/virtualNetworkLinks" \
  --created \
  --interval $POLL_INTERVAL \
  --timeout $MAX_TIMEOUT

log_with_timestamp "Waiting for App Configuration: $APP_CONFIGURATION_ENDPOINT"
time az resource wait \
  --resource-group "$RESOURCE_GROUP" \
  --ids "$APP_CONFIGURATION_ID" \
  --namespace "Microsoft.AppConfiguration" \
  --resource-type "configurationStores" \
  --created \
  --interval $POLL_INTERVAL \
  --timeout $MAX_TIMEOUT

log_with_timestamp "Waiting for Storage Account: $STORAGE_ACCOUNT_NAME"
time az resource wait \
  --resource-group "$RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT_NAME" \
  --namespace "Microsoft.Storage" \
  --resource-type "storageAccounts" \
  --created \
  --interval $POLL_INTERVAL \
  --timeout $MAX_TIMEOUT

# Waits for specific keys in Application Config
waitForAppConfigKey "graphdb-cluster-token"
waitForAppConfigKey "graphdb-password"
waitForAppConfigKey "graphdb-license"

echo "#########################################################"
echo "# Finished waiting for dependent resources and services #"
echo "#########################################################"
