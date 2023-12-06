#!/bin/bash

set -euxo pipefail

#
# Cluster creation
#

RESOURCE_GROUP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
GRAPHDB_ADMIN_PASSWORD="$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-password --query "value" --output tsv)"
DNS_ZONE_NAME=$(az network private-dns zone list --query "[].name" --output tsv)
INSTANCE_ID=$(basename $(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
VMSS_NAME=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-01-01&format=text")
INSTANCE_IDS=($(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[].instanceId" --output tsv))
SORTED_INSTANCE_IDs=($(echo "$${INSTANCE_IDS[@]}" | tr ' ' '\n' | sort))
LOWEST_INSTANCE_ID=$${SORTED_INSTANCE_IDs[0]}


check_gdb() {
  local gdb_address="$1:7200/protocol"
  if curl -s --head -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" --fail $gdb_address > /dev/null; then
    return 0 # Success, endpoint is available
  else
    return 1 # Endpoint not available yet
  fi
}

# Waits for 3 DNS records to be available
wait_dns_records() {
  ALL_FQDN_RECORDS_COUNT=($(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, 'node')].fqdn | length(@)"))
  if [ "$${ALL_FQDN_RECORDS_COUNT}" -ne 3 ]; then
    sleep 5
    wait_dns_records
  fi
}

wait_dns_records

if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then
  for record in "$${ALL_FQDN_RECORDS[@]}"; do
    # Removes the '.' at the end of the DNS address
    cleanedAddress=$${record%?}
    while ! check_gdb "$cleanedAddress"; do
      echo "Waiting for GDB $record to start"
      sleep 5
    done
  done

  echo "All GDB instances are available. Creating cluster"
  # Checks if the cluster already exists
  IS_CLUSTER=$(curl -s -o /dev/null -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" -w "%%{http_code}" http://localhost:7200/rest/monitor/cluster)

  if [ "$IS_CLUSTER" != 200 ]; then
    for ((i = 1; i <= 3; i++)); do
      CLUSTER_CREATION=$(
        curl -X POST http://localhost:7200/rest/cluster/config \
          -w "%%{http_code}" \
          -H 'Content-type: application/json' \
          -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" \
          -d "{\"nodes\": [\"node-1.$${DNS_ZONE_NAME}:7300\",\"node-2.$${DNS_ZONE_NAME}:7300\",\"node-3.$${DNS_ZONE_NAME}:7300\"]}"
      )

      if [ "$CLUSTER_CREATION" -eq 200 ]; then
        echo "Cluster created successfully."
        break
      else
        echo "Failed to create cluster (HTTP response code: $CLUSTER_CREATION). Retrying in $RETRY_DELAY seconds..."
        sleep 5
      fi
    done
  else
    echo "Cluster exists"
  fi
fi
