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

set -euo pipefail

echo "#######################################"
echo "#   GraphDB configuration overrides   #"
echo "#######################################"

RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
DNS_ZONE_NAME=${private_dns_zone_name}
RECORD_NAME=$(cat /tmp/node_name)
APP_CONFIG_ENDPOINT=${app_configuration_endpoint}

echo "Getting secrets"
secrets=$(az appconfig kv list --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login | jq .[].key)

echo "Getting GraphDB license"
az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_license_secret_name} | jq -r .value | base64 -d > /etc/graphdb/graphdb.license

echo "Getting the cluster token"
graphdb_cluster_token=$(az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_cluster_token_name} | jq -r .value | base64 -d)

echo "Getting the full DNS record for current instance"
NODE_DNS=$(az network private-dns record-set a show --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --output tsv --query "fqdn" | rev | cut -c 2- | rev)

echo "Writing override files"
# TODO: where is the vhost here?
cat <<EOF > /etc/graphdb/graphdb.properties
graphdb.auth.token.secret=$graphdb_cluster_token
graphdb.connector.port=7200
graphdb.external-url=http://$${NODE_DNS}:7200/
graphdb.rpc.address=$${NODE_DNS}:7300
EOF

cat <<EOF > /etc/graphdb-cluster-proxy/graphdb.properties
graphdb.auth.token.secret=$graphdb_cluster_token
graphdb.connector.port=7201
graphdb.external-url=https://${graphdb_external_address_fqdn}
graphdb.vhosts=https://${graphdb_external_address_fqdn},http://$${NODE_DNS}:7201
graphdb.rpc.address=$${NODE_DNS}:7301
graphdb.proxy.hosts=$${NODE_DNS}:7300
EOF

echo "Calculating 85 percent of total memory"
# Get total memory in kilobytes
total_memory_kb=$(grep -i "MemTotal" /proc/meminfo | awk '{print $2}')
# Convert total memory to gigabytes
total_memory_gb=$(echo "scale=2; $total_memory_kb / 1024 / 1024" | bc)
# Calculate 85% of total VM memory
jvm_max_memory=$(echo "$total_memory_gb * 0.85" | bc | cut -d'.' -f1)

mkdir -p /etc/systemd/system/graphdb.service.d/

cat <<EOF > /etc/systemd/system/graphdb.service.d/overrides.conf
[Service]
Environment="GDB_HEAP_SIZE=$${jvm_max_memory}g"
EOF

# TODO: overrides for the proxy?
# Appends configuration overrides to graphdb.properties
if [[ $secrets == *"${graphdb_properties_secret_name}"* ]]; then
  echo "Using graphdb.properties overrides"
  az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_properties_secret_name} | jq -r .value | base64 -d >> /etc/graphdb/graphdb.properties
fi

# Appends environment overrides to GDB_JAVA_OPTS
if [[ $secrets == *"${graphdb_java_options_secret_name}"* ]]; then
  echo "Using GDB_JAVA_OPTS overrides"
  extra_graphdb_java_options=$(az appconfig kv show --endpoint "$APP_CONFIG_ENDPOINT" --auth-mode login --key ${graphdb_java_options_secret_name} | jq -r .value | base64 -d)
  (
    source /etc/graphdb/graphdb.env
    echo "GDB_JAVA_OPTS=\"$GDB_JAVA_OPTS $extra_graphdb_java_options\"" >> /etc/graphdb/graphdb.env
  )
fi

echo "Completed applying overrides"
