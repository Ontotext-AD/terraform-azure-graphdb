#!/bin/bash

# This script focuses on DNS provisioning in an Azure environment for instances within a VMSS.
#
# It performs the following tasks:
#  * Retrieves metadata about the Azure instance, including the resource group, IP address, and VMSS name.
#  * Gathers the DNS zone name from the provided environment variable.
#  * Checks for existing DNS records associated with the instance's IP address.
#    * If a DNS record exists, updates it with the current instance's IP address.
#    * If no DNS record exists, creates a new one with an incremented name.
#  * Sets the hostname of the instance to match the DNS record name.
#  * Saves relevant information to files for use in subsequent scripts.

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

echo "########################"
echo "#   DNS Provisioning   #"
echo "########################"
# This provides stable network addresses for GDB instances in Azure VMSS

RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
IP_ADDRESS=$(hostname -I | awk '{print $1}')
DNS_ZONE_NAME=${private_dns_zone_name}
NODE_DNS_PATH="/var/opt/graphdb/node_dns_name"
NODE_NUMBER=1

###########################################################################################################
# This will be removed in the future, it's required for migration between TF module version 1.0.x and 1.1.x
IP_RECORD_PRESENT=$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?aRecords[?ipv4Address=='$IP_ADDRESS'].ipv4Address].name" --output tsv)

if [ "$IP_RECORD_PRESENT" ]  && [ -z "$NODE_DNS_PATH" ]; then
  log_with_timestamp "Recovering node_dns_name by current IP address"
  echo "$IP_RECORD_PRESENT" > $NODE_DNS_PATH
fi
###########################################################################################################

if [ -f $NODE_DNS_PATH ]; then
  log_with_timestamp "Found $NODE_DNS_PATH"
  NODE_DNS_RECORD=$(cat $NODE_DNS_PATH)

  # Updates the NODE_DSN record on file with the new IP.
  log_with_timestamp "Updating IP address for $NODE_DNS_RECORD"
  # We need to recreate the record to update the IP, cannot update with the same IP.
  az network private-dns record-set a delete --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $NODE_DNS_RECORD --yes || true
  az network private-dns record-set a add-record --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --record-set-name $NODE_DNS_RECORD --ipv4-address "$IP_ADDRESS"

  hostnamectl set-hostname "$NODE_DNS_RECORD"
  log_with_timestamp "DNS record for $NODE_DNS_RECORD has been updated"
else
  log_with_timestamp "$NODE_DNS_PATH does not exist. New DNS record will be created."

  while true; do
    # Concatenate "node" with the extracted number
    NODE_NAME="node-$NODE_NUMBER"

    # Check if the record exists for the node name in the Private DNS zone
    DNS_RECORD_TAKEN=$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?name=='$NODE_NAME'].name" --output tsv)

    if [ "$DNS_RECORD_TAKEN" ]; then
      # Increment node number for the next iteration
      NODE_NUMBER=$((NODE_NUMBER + 1))
    else
      log_with_timestamp "Record $NODE_NAME does not exist"
      NODE_DNS_RECORD=$NODE_NAME
      # Creates the record
      if az network private-dns record-set a create --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $NODE_NAME &>/dev/null &&
        az network private-dns record-set a add-record --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --record-set-name $NODE_NAME --ipv4-address "$IP_ADDRESS" &>/dev/null; then
        log_with_timestamp "DNS record for $NODE_DNS_RECORD has been created"
        hostnamectl set-hostname "$NODE_DNS_RECORD"
        echo $NODE_NAME > $NODE_DNS_PATH
        break # Exit loop when non-existing node name is found
      else
        log_with_timestamp "Creating DNS record failed for $NODE_NAME, retrying with next available name"
        # Retry with the next node number
        NODE_NUMBER=$((NODE_NUMBER + 1))
      fi
    fi
  done
fi
