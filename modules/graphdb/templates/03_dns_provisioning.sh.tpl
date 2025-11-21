#!/bin/bash

# This script focuses on DNS provisioning in an Azure environment for instances within a VMSS.
#
# It performs the following tasks:
#  * Retrieves metadata about the Azure instance, including the resource group, IP address, and VMSS name.
#  * Gathers the DNS zone name from the provided environment variable.
#  * Checks for existing DNS records associated with the instance's IP address.
#    * If a DNS record exists for this IP, reuses that node name.
#    * If no DNS record exists for this IP, reuses an idle node-* record (no service responding), or creates a new one.
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
DNS_ZONE_NAME="${private_dns_zone_name}"
EXPECTED_NODE_COUNT="${node_count}"
NODE_DNS_PATH="/var/opt/graphdb/node_dns_name"
NODE_NUMBER=1

SERVICE_PORT="$${GRAPHDB_SERVICE_PORT:-7200}"
HEALTH_TIMEOUT_SECONDS=2
HEALTH_PATH="$${GRAPHDB_HEALTH_PATH:-/protocol}"

########################################
# Helper functions
########################################

# HTTP-based health check using curl to an IP or host
is_service_alive() {
  local host="$1"
  local port="$2"

  local url="http://$${host}:$${port}$${HEALTH_PATH}"

  if curl -fsS --max-time "$HEALTH_TIMEOUT_SECONDS" "$url" >/dev/null 2>&1; then
    # service is alive
    return 0
  else
    # service not reachable / unhealthy
    return 1
  fi
}

find_idle_dns_record() {
  # IMPORTANT: send logs to stderr so they don't get captured by command substitution
  log_with_timestamp "Searching for idle DNS record in zone $${DNS_ZONE_NAME}" >&2

  # List all A record-sets in the private DNS zone
  mapfile -t EXISTING_RECORDS < <(
    az network private-dns record-set list \
      --zone-name "$${DNS_ZONE_NAME}" \
      --resource-group "$${RESOURCE_GROUP}" \
      --query "[?type=='Microsoft.Network/privateDnsZones/A'].name" \
      --output tsv
  )

  for NODE_NAME in "$${EXISTING_RECORDS[@]}"; do
    # Only consider node-* records
    [[ "$${NODE_NAME}" != node-* ]] && continue

    # Get first A record IP for this record-set
    IP=$(az network private-dns record-set a show \
      --zone-name "$${DNS_ZONE_NAME}" \
      --resource-group "$${RESOURCE_GROUP}" \
      --name "$${NODE_NAME}" \
      --query "aRecords[0].ipv4Address" \
      --output tsv 2>/dev/null || true)

    # An idle node record is determined by /protocol not responding
    if ! is_service_alive "$${IP}" "$${SERVICE_PORT}"; then
      log_with_timestamp "Found idle DNS record (service down): $${NODE_NAME} (IP $${IP}:$${SERVICE_PORT}$${HEALTH_PATH})" >&2
      echo "$${NODE_NAME}"
      return 0
    fi
  done

  # No idle record found
  return 1
}

###########################################################################################################
# Check if any DNS record already has this IP
###########################################################################################################
IP_RECORD_PRESENT=$(az network private-dns record-set list \
  --zone-name "$${DNS_ZONE_NAME}" \
  --resource-group "$${RESOURCE_GROUP}" \
  --query "[?aRecords[?ipv4Address=='$${IP_ADDRESS}'].ipv4Address].name" \
  --output tsv)

# If there is a record pointing to this IP, we just reuse that node name.
if [ -n "$${IP_RECORD_PRESENT}" ]; then
  NODE_DNS_RECORD="$${IP_RECORD_PRESENT}"
  log_with_timestamp "Found existing DNS record $${NODE_DNS_RECORD} for IP $${IP_ADDRESS}, reusing"

  # Ensure node_dns_name file is in sync
  if [ ! -d "$(dirname "$${NODE_DNS_PATH}")" ]; then
    mkdir -p "$(dirname "$${NODE_DNS_PATH}")"
  fi

  if [ ! -f "$${NODE_DNS_PATH}" ] || [ "$(cat "$${NODE_DNS_PATH}")" != "$${NODE_DNS_RECORD}" ]; then
    echo "$${NODE_DNS_RECORD}" > "$${NODE_DNS_PATH}"
  fi

  # Ensure hostname matches the DNS record
  hostnamectl set-hostname "$${NODE_DNS_RECORD}"
  log_with_timestamp "Hostname set to $${NODE_DNS_RECORD} (IP already registered in DNS)"
  exit 0
fi

###########################################################################################################
# If NO record has this IP, we either reuse an idle record, or create a new one.
###########################################################################################################
log_with_timestamp "No DNS record currently uses IP $${IP_ADDRESS}."

# Count existing node-* DNS records to avoid breaking initial setup
CURRENT_NODE_DNS_COUNT=$(az network private-dns record-set list \
  --zone-name "$${DNS_ZONE_NAME}" \
  --resource-group "$${RESOURCE_GROUP}" \
  --query "[?type=='Microsoft.Network/privateDnsZones/A' && starts_with(name, 'node-')].name" \
  --output tsv | wc -w)

if [ "$${CURRENT_NODE_DNS_COUNT}" -ne "$${EXPECTED_NODE_COUNT}" ]; then
  # During initial setup, skip idle reuse to avoid stealing names.
  log_with_timestamp "Current node-* DNS record count ($${CURRENT_NODE_DNS_COUNT}) does not match expected ($${EXPECTED_NODE_COUNT}). Skipping idle record reuse; proceeding to create a new node-N record."
  IDLE_RECORD_NAME=""
else
  log_with_timestamp "Current node-* DNS record count matches expected ($${EXPECTED_NODE_COUNT}). Searching for idle node-* record to reuse."
  # Try to reuse an existing node-* record whose service is not active
  if ! IDLE_RECORD_NAME=$(find_idle_dns_record); then
    IDLE_RECORD_NAME=""
  fi
fi

if [ -n "$${IDLE_RECORD_NAME}" ]; then
  NODE_DNS_RECORD="$${IDLE_RECORD_NAME}"
  log_with_timestamp "Reusing idle DNS record: $${NODE_DNS_RECORD}"

  # Drop old record-set then recreate for this node
  az network private-dns record-set a delete \
    --resource-group "$${RESOURCE_GROUP}" \
    --zone-name "$${DNS_ZONE_NAME}" \
    --name "$${NODE_DNS_RECORD}" \
    --yes || true

  az network private-dns record-set a create \
    --resource-group "$${RESOURCE_GROUP}" \
    --zone-name "$${DNS_ZONE_NAME}" \
    --name "$${NODE_DNS_RECORD}" >/dev/null

  az network private-dns record-set a add-record \
    --resource-group "$${RESOURCE_GROUP}" \
    --zone-name "$${DNS_ZONE_NAME}" \
    --record-set-name "$${NODE_DNS_RECORD}" \
    --ipv4-address "$${IP_ADDRESS}" >/dev/null

  # Ensure path exists
  if [ ! -d "$(dirname "$${NODE_DNS_PATH}")" ]; then
    mkdir -p "$(dirname "$${NODE_DNS_PATH}")"
  fi

  hostnamectl set-hostname "$${NODE_DNS_RECORD}"
  echo "$${NODE_DNS_RECORD}" > "$${NODE_DNS_PATH}"
  log_with_timestamp "DNS record for $${NODE_DNS_RECORD} has been reassigned to this node (IP $${IP_ADDRESS})"

else
  # 3) Fallback to "first free node-N" logic
  log_with_timestamp "No idle DNS record found (or initial setup). New DNS record will be created."

  while true; do
    NODE_NAME="node-$${NODE_NUMBER}"

    DNS_RECORD_TAKEN=$(az network private-dns record-set list \
      --zone-name "$${DNS_ZONE_NAME}" \
      --resource-group "$${RESOURCE_GROUP}" \
      --query "[?name=='$${NODE_NAME}'].name" \
      --output tsv)

    if [ -n "$${DNS_RECORD_TAKEN}" ]; then
      # Increment node number for the next iteration
      NODE_NUMBER=$((NODE_NUMBER + 1))
    else
      log_with_timestamp "Record $${NODE_NAME} does not exist"
      NODE_DNS_RECORD="$${NODE_NAME}"

      if az network private-dns record-set a create \
            --resource-group "$${RESOURCE_GROUP}" \
            --zone-name "$${DNS_ZONE_NAME}" \
            --name "$${NODE_NAME}" >/dev/null &&
         az network private-dns record-set a add-record \
            --resource-group "$${RESOURCE_GROUP}" \
            --zone-name "$${DNS_ZONE_NAME}" \
            --record-set-name "$${NODE_NAME}" \
            --ipv4-address "$${IP_ADDRESS}" >/dev/null; then

        log_with_timestamp "DNS record for $${NODE_DNS_RECORD} has been created"

        if [ ! -d "$(dirname "$${NODE_DNS_PATH}")" ]; then
          mkdir -p "$(dirname "$${NODE_DNS_PATH}")"
        fi

        hostnamectl set-hostname "$${NODE_DNS_RECORD}"
        echo "$${NODE_NAME}" > "$${NODE_DNS_PATH}"
        break
      else
        log_with_timestamp "Creating DNS record failed for $${NODE_NAME}, retrying with next available name"
        NODE_NUMBER=$((NODE_NUMBER + 1))
      fi
    fi
  done
fi
