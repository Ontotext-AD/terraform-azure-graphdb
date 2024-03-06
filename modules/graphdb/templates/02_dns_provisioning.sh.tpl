#!/bin/bash

# This script focuses on DNS provisioning in an Azure environment for instances within a VMSS.
#
# It performs the following tasks:
#   * Retrieves metadata about the Azure instance, including the resource group, IP address, VMSS name, and instance ID.
#   * Waits for the DNS zone to be created and role assigned.
#   * Gathers all FQDN records from the private DNS zone containing "node."
#   * Retrieves and sorts instance IDs for the current VMSS.
#   * Identifies the lowest, middle, and highest instance IDs.
#   * Pings DNS records and updates them with the current instance's IP address if necessary.
#   * Assigns DNS record names based on instance ID, creating records if they don't exist.
#   * Saves relevant information to temporary files for use in subsequent scripts.

set -euo pipefail

echo "########################"
echo "#   DNS Provisioning   #"
echo "########################"
# This provides stable network addresses for GDB instances in Azure VMSS

RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
IP_ADDRESS=$(hostname -I | awk '{print $1}')
VMSS_NAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-01-01&format=text")
INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
DNS_ZONE_NAME=${private_dns_zone_name}

# Get all FQDN records from the private DNS zone containing "node"
readarray -t ALL_FQDN_RECORDS <<< "$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, 'node')].fqdn" --output tsv)"
# Get all instance IDs for the current VMSS
INSTANCE_IDS=($(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[].instanceId" --output tsv))
# Sort instance IDs
SORTED_INSTANCE_IDS=($(echo "$${INSTANCE_IDS[@]}" | tr ' ' '\n' | sort -n))
# Find the lowest, middle and highest instance IDs
LOWEST_INSTANCE_ID=$${SORTED_INSTANCE_IDS[0]}
MIDDLE_INSTANCE_ID=$${SORTED_INSTANCE_IDS[1]}
HIGHEST_INSTANCE_ID=$${SORTED_INSTANCE_IDS[2]}

# Saving this to a file as it is required by 06_cluster_setup.sh.tpl
echo $LOWEST_INSTANCE_ID > /tmp/lowest_id

# Pings a DNS record, if no response is returned, will update the DNS record with the IP of the current instance
ping_and_set_dns_record() {
  local DNS_RECORD="$1"
  # Checks if a record with the current instance IP is present
  IP_RECORD_PRESENT=$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?aRecords[?ipv4Address=='$IP_ADDRESS'].ipv4Address].name" --output tsv)
  # If no record is present for the current IP check, which node is missing and assign the IP to it.
  if [ -z "$IP_RECORD_PRESENT" ]; then
    echo "Pinging $DNS_RECORD"
      if ping -c 5 "$DNS_RECORD"; then
        echo "Ping successful"
      else
        echo "Ping failed for $DNS_RECORD"
        # Extracts the record name
        RECORD_NAME=$(echo "$DNS_RECORD" | awk -F'.' '{print $1}')
        az network private-dns record-set a update --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --set ARecords[0].ipv4Address="$IP_ADDRESS"
      fi
  else
    echo "Record for this IP is present in the Private DNS"
  fi
}

# Assign DNS record name based on instanceId
for i in "$${!SORTED_INSTANCE_IDS[@]}"; do
  if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then
    RECORD_NAME="node-1"
  elif [ "$INSTANCE_ID" == "$${MIDDLE_INSTANCE_ID}" ]; then
    RECORD_NAME="node-2"
  elif [ "$INSTANCE_ID" == "$${HIGHEST_INSTANCE_ID}" ]; then
    RECORD_NAME="node-3"
  fi

  # Saving this to file as it is required in 03_gdb_conf_overrides.sh.tpl
  echo $RECORD_NAME > /tmp/node_name

  # Get the FQDN for the current instance
  FQDN=$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, '$RECORD_NAME')].fqdn" --output tsv)

  if [ -z "$${FQDN:-}" ]; then
    # Have to first create and then add, see https://github.com/Azure/azure-cli/issues/27374
    az network private-dns record-set a create --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME
    az network private-dns record-set a add-record --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --record-set-name $RECORD_NAME --ipv4-address "$IP_ADDRESS"
  else
    for record in "$${ALL_FQDN_RECORDS[@]}"; do
      echo "Checking DNS record $record"
      ping_and_set_dns_record "$record"
    done
  fi

  break
done
