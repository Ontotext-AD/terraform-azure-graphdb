#!/bin/bash

# This script focuses on configuring GraphDB instances in an Azure environment with specific overrides.
#
# It performs the following tasks:
#   * Retrieves metadata about the Azure instance, including the resource group, DNS zone name, and record name.
#   * Retrieves secrets and configuration values from Azure App Configuration.
#   * Writes the GraphDB license, cluster token, and DNS record details to relevant configuration files.
#   * Calculates 85% of the total memory and sets JVM maximum memory accordingly.
#   * Creates systemd service overrides for GraphDB based on memory calculations.
#   * Applies optional overrides for graphdb.properties and GDB_JAVA_OPTS from Azure App Configuration secrets.

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

echo "#######################################"
echo "#   GraphDB configuration overrides   #"
echo "#######################################"

RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
DNS_ZONE_NAME=${private_dns_zone_name}
APP_CONFIG_ENDPOINT=${app_configuration_endpoint}
GRAPHDB_NODE_COUNT="$(az appconfig kv show \
  --endpoint ${app_configuration_endpoint} \
  --auth-mode login \
  --key node_count \
  | jq -r .value)"

log_with_timestamp "Getting secrets"
secrets=$(az appconfig kv list --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login | jq .[].key)

log_with_timestamp "Getting GraphDB license"
az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_license_secret_name} | jq -r .value | base64 -d >/etc/graphdb/graphdb.license

log_with_timestamp "Writing configuration files"

CLEAN_CONTEXT_PATH=$(echo "${context_path}" | sed 's#^/*##' | sed 's#/*$##')

# graphdb.external-url.enforce.transactions: determines whether it is necessary to rewrite the Location header when no proxy is configured.
# This is required because when working with the GDB transaction endpoint it returns an erroneous URL with HTTP protocol instead of HTTPS
if [ "$GRAPHDB_NODE_COUNT" -eq 1 ]; then
if [ -n "${context_path}" ]; then
  EXTERNAL_URL="https://${graphdb_external_address_fqdn}/$${CLEAN_CONTEXT_PATH}"
else
  EXTERNAL_URL="https://${graphdb_external_address_fqdn}"
fi

cat <<EOF >/etc/graphdb/graphdb.properties
graphdb.connector.port=7200
graphdb.external-url=$${EXTERNAL_URL}
graphdb.external-url.enforce.transactions=true
EOF
else
  RECORD_NAME=$(cat /var/opt/graphdb/node_dns_name)

  log_with_timestamp "Getting the cluster token"
  graphdb_cluster_token=$(az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_cluster_token_name} | jq -r .value | base64 -d )
  log_with_timestamp "Getting the full DNS Record for current instance"

  NODE_DNS=$(az network private-dns record-set a show --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --output tsv --query "fqdn" | rev | cut -c 2- | rev)

if [ -n "${context_path}" ]; then
  VHOSTS_VALUE="https://${graphdb_external_address_fqdn}/$${CLEAN_CONTEXT_PATH},http://$${NODE_DNS}:7200"
else
  VHOSTS_VALUE="https://${graphdb_external_address_fqdn},http://$${NODE_DNS}:7200"
fi

cat <<EOF >/etc/graphdb/graphdb.properties
graphdb.auth.token.secret=$graphdb_cluster_token
graphdb.connector.port=7200
graphdb.vhosts=$${VHOSTS_VALUE}
graphdb.external-url=http://$${NODE_DNS}:7200
graphdb.rpc.address=$${NODE_DNS}:7300
EOF

if [ -n "${context_path}" ]; then
  EXTERNAL_URL="https://${graphdb_external_address_fqdn}/$${CLEAN_CONTEXT_PATH}"
else
  EXTERNAL_URL="https://${graphdb_external_address_fqdn}"
fi

cat <<EOF >/etc/graphdb-cluster-proxy/graphdb.properties
graphdb.auth.token.secret=$graphdb_cluster_token
graphdb.connector.port=7201
graphdb.vhosts=$${VHOSTS_VALUE}
graphdb.external-url=$${EXTERNAL_URL}
graphdb.rpc.address=$${NODE_DNS}:7301
graphdb.proxy.hosts=$${NODE_DNS}:7300
EOF
fi

log_with_timestamp "Calculating 85 percent of total memory"
# Get total memory in kilobytes
total_memory_kb=$(grep -i "MemTotal" /proc/meminfo | awk '{print $2}')
# Convert total memory into gigabytes
total_memory_gb=$(echo "scale=2; $total_memory_kb / 1024 / 1024" | bc)
jvm_max_memory=$(echo "$total_memory_gb * 0.85" | bc | cut -d'.' -f1)

mkdir -p /etc/systemd/system/graphdb.service.d/

cat <<EOF >/etc/systemd/system/graphdb.service.d/overrides.conf
[Service]
Environment="GDB_HEAP_SIZE=$${jvm_max_memory}g"
EOF

if [[ $secrets == *"${graphdb_properties_secret_name}"* ]]; then
  log_with_timestamp "Using graphdb.properties overrides"
  az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_properties_secret_name} | jq -r .value | base64 -d >>/etc/graphdb/graphdb.properties
fi

if [[ $secrets == *"${graphdb_java_options_secret_name}"* ]]; then
  log_with_timestamp "Using GDB_JAVA_OPTS overrides"
  extra_graphdb_java_options=$(az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_java_options_secret_name} | jq -r .value | base64 -d)
  if grep GDB_JAVA_OPTS &>/dev/null /etc/graphdb/graphdb.env; then
    sed -ie "s/GDB_JAVA_OPTS=\"\(.*\)\"/GDB_JAVA_OPTS=\"\1 $extra_graphdb_java_options\"/g" /etc/graphdb/graphdb.env
  else
    echo "GDB_JAVA_OPTS=$extra_graphdb_java_options" > /etc/graphdb/graphdb.env
  fi
fi

# Remove sudo privileges for all local users - they don't need this permission and is a high security risk
log_with_timestamp "Re-configure user permissions"
[[ -f /etc/sudoers.d/90-cloud-init-users ]] && rm /etc/sudoers.d/90-cloud-init-users

log_with_timestamp "Completed applying overrides"
