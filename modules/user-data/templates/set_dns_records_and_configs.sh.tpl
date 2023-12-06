#!/bin/bash

#
# DNS setup
# This provides stable network addresses for GDB instances in Azure VMSS
#

RESOURCE_GROUP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
VMSS_NAME=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-01-01&format=text")
INSTANCE_ID=$(basename $(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
IP_ADDRESS=$(hostname -I | awk '{print $1}')

for i in $(seq 1 6); do
  # Waits for DNS zone to be created and role assigned
  DNS_ZONE_NAME=$(az network private-dns zone list --query "[].name" --output tsv)
  if [ -z "$${DNS_ZONE_NAME:-}" ]; then
    echo 'Zone not available yet'
    sleep 10
  else
    break
  fi
done

# Get all FQDN records from the private DNS zone containing "node"
ALL_FQDN_RECORDS=($(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, 'node')].fqdn" --output tsv))
# Get all instance IDs for a specific VMSS
INSTANCE_IDS=($(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[].instanceId" --output tsv))
# Sort instance IDs
SORTED_INSTANCE_IDs=($(echo "$${INSTANCE_IDS[@]}" | tr ' ' '\n' | sort))
# Find the lowest, middle and highest instance IDs
LOWEST_INSTANCE_ID=$${SORTED_INSTANCE_IDs[0]}
MIDDLE_INSTANCE_ID=$${SORTED_INSTANCE_IDs[1]}
HIGHEST_INSTANCE_ID=$${SORTED_INSTANCE_IDs[2]}

# Will ping a DNS record, if no response is returned, will update the DNS record with the IP of the instance
ping_and_set_dns_record() {
  local dns_record="$1"
  echo "Pinging $dns_record"
  if ping -c 5 "$dns_record"; then
    echo "Ping successful"
  else
    echo "Ping failed for $dns_record"
    # Extracts the record name
    RECORD_NAME=$(echo "$dns_record" | awk -F'.' '{print $1}')
    az network private-dns record-set a update --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --set ARecords[0].ipv4Address="$IP_ADDRESS"
  fi
}

# assign DNS record name based on instanceId
for i in "$${!SORTED_INSTANCE_IDs[@]}"; do
  if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then
    RECORD_NAME="node-1"
  elif [ "$INSTANCE_ID" == "$${MIDDLE_INSTANCE_ID}" ]; then
    RECORD_NAME="node-2"
  elif [ "$INSTANCE_ID" == "$${HIGHEST_INSTANCE_ID}" ]; then
    RECORD_NAME="node-3"
  fi
  # Get the FQDN for the current instance
  FQDN=$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, '$RECORD_NAME')].fqdn" --output tsv)

  if [ -z "$${FQDN:-}" ]; then
    az network private-dns record-set a add-record --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --record-set-name $RECORD_NAME --ipv4-address "$IP_ADDRESS"
  else
    for record in "$${ALL_FQDN_RECORDS[@]}"; do
      ping_and_set_dns_record "$record"
    done
  fi

  break
done

#
# GraphDB configuration overrides
#

SECRETS=$(az keyvault secret list --vault-name ${key_vault_name} --output json | jq .[].name)

# Gets the full DNS record for the current instance
NODE_DNS=$(az network private-dns record-set a show --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --output tsv --query "fqdn" | rev | cut -c 2- | rev)

# Get the license
az keyvault secret download --vault-name ${key_vault_name} --name graphdb-license --file /etc/graphdb/graphdb.license --encoding base64

# Get the cluster token
graphdb_cluster_token=$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-cluster-token | jq -rj .value | base64 -d)

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

# Get total memory in kilobytes
total_memory_kb=$(grep -i "MemTotal" /proc/meminfo | awk '{print $2}')

# Convert total memory to gigabytes
total_memory_gb=$(echo "scale=2; $total_memory_kb / 1024 / 1024" | bc)

# Calculate 85% of total memory
jvm_max_memory=$(echo "$total_memory_gb * 0.85" | bc | cut -d'.' -f1)

mkdir -p /etc/systemd/system/graphdb.service.d/

cat <<EOF > /etc/systemd/system/graphdb.service.d/overrides.conf
[Service]
Environment="GDB_HEAP_SIZE=$${jvm_max_memory}g"
EOF

# TODO: overrides for the proxy?
# Appends configuration overrides to graphdb.properties
if [[ $SECRETS == *"graphdb-properties"* ]]; then
  echo "Using graphdb.properties overrides"
  az keyvault secret show --vault-name ${key_vault_name} --name graphdb-properties | jq -rj .value | base64 -d >>/etc/graphdb/graphdb.properties
fi

# Appends environment overrides to GDB_JAVA_OPTS
if [[ $SECRETS == *"graphdb-java-options"* ]]; then
  echo "Using GDB_JAVA_OPTS overrides"
  extra_graphdb_java_options=$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-java-options | jq -rj .value | base64 -d)
  (
    source /etc/graphdb/graphdb.env
    echo "GDB_JAVA_OPTS=$GDB_JAVA_OPTS $extra_graphdb_java_options" >> /etc/graphdb/graphdb.env
  )
fi
