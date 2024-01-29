#!/bin/bash

# This script focuses on the GraphDB cluster creation and enabling the security.
#
# It performs the following tasks:
#   * Retrieves essential metadata about the Azure instance, including the instance ID, RG, DNS zone name, and GraphDB password.
#   * Initiates GraphDB and enables the GraphDB cluster proxy service.
#   * Monitors the availability of GraphDB instances using DNS records and waits for all instances to be running.
#   * If the current instance has the lowest ID, it attempts to create a GraphDB cluster, retries if necessary, and confirms the cluster's existence.
#   * Changes the admin user password and enables security if not already enabled.
#   * Displays appropriate messages for successful completion or potential errors.

set -euo pipefail

echo "###########################"
echo "#    Starting GraphDB     #"
echo "###########################"

INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
DNS_ZONE_NAME=$(az network private-dns zone list --query "[].name" --output tsv)
GRAPHDB_ADMIN_PASSWORD="$(az appconfig kv show --name ${app_config_name} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
MAX_RETRIES=3
RETRY_DELAY=5

systemctl daemon-reload
systemctl start graphdb
systemctl enable graphdb-cluster-proxy.service
systemctl start graphdb-cluster-proxy.service

echo "##################################"
echo "#    Beginning cluster setup     #"
echo "##################################"

check_gdb() {
  if [ -z "$1" ]; then
    echo "Error: IP address or hostname is not provided."
    return 1
  fi

  local gdb_address="$1:7200/rest/monitor/infrastructure"
  if curl -s --head -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" --fail "$gdb_address" >/dev/null; then
    echo "Success, GraphDB node $gdb_address is available"
    return 0
  else
    echo "GraphDB node $gdb_address is not available yet"
    return 1
  fi
}

# Waits for 3 DNS records to be available
wait_dns_records() {
  ALL_FQDN_RECORDS_COUNT=($(
    az network private-dns record-set list \
      --zone $DNS_ZONE_NAME \
      --resource-group $RESOURCE_GROUP \
      --query "[?contains(name, 'node')].fqdn | length(@)"
  ))

  if [ "$${ALL_FQDN_RECORDS_COUNT}" -ne 3 ]; then
    sleep 5
    wait_dns_records
  else
    echo "Private DNS zone record count is $${ALL_FQDN_RECORDS_COUNT}"
  fi
}

wait_dns_records

readarray -t ALL_DNS_RECORDS <<<"$(az network private-dns record-set list \
  --zone $DNS_ZONE_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'node')].fqdn" \
  --output tsv)"

# Check all instances are running
for record in "$${ALL_DNS_RECORDS[@]}"; do
  echo "Pinging $record"
  # Removes the '.' at the end of the DNS address
  cleanedAddress=$${record%?}
  # Check if cleanedAddress is non-empty before calling check_gdb
  if [ -n "$cleanedAddress" ]; then
    while ! check_gdb "$cleanedAddress"; do
      echo "Waiting for GDB $cleanedAddress to start"
      sleep "$RETRY_DELAY"
    done
  else
    echo "Error: cleanedAddress is empty."
  fi
done

echo "All GDB instances are available. Creating the cluster."

LOWEST_INSTANCE_ID=$(cat /tmp/lowest_id)

#  Only the instance with the lowest ID would attempt to create the cluster
if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then

  for ((i = 1; i <= $MAX_RETRIES; i++)); do
    IS_CLUSTER=$(
      curl -s -o /dev/null \
        -u "admin:$GRAPHDB_ADMIN_PASSWORD" \
        -w "%%{http_code}" \
        http://localhost:7200/rest/monitor/cluster
    )

    # 000 = no HTTP code was received
    if [[ "$IS_CLUSTER" == 000 ]]; then
      echo "Retrying ($i/$MAX_RETRIES) after $RETRY_DELAY seconds..."
      sleep $RETRY_DELAY
    elif [ "$IS_CLUSTER" == 503 ]; then
      CLUSTER_CREATED=$(
        curl -X POST -s http://localhost:7200/rest/cluster/config \
          -w "%%{http_code}" \
          -H 'Content-type: application/json' \
          -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" \
          -d "{\"nodes\": [\"node-1.$${DNS_ZONE_NAME}:7300\",\"node-2.$${DNS_ZONE_NAME}:7300\",\"node-3.$${DNS_ZONE_NAME}:7300\"]}"
      )
      if [[ "$CLUSTER_CREATED" == 200 ]]; then
        echo "GraphDB cluster successfully created!"
        break
      fi
    elif [ "$IS_CLUSTER" == 200 ]; then
      echo "Cluster exists"
      break
    else
      echo "Something went wrong! Check the logs."
    fi
  done
fi

echo "###########################################################"
echo "#    Changing admin user password and enable security     #"
echo "###########################################################"

is_security_enabled=$(curl -s -X GET \
  --header 'Accept: application/json' \
  -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" \
  'http://localhost:7200/rest/security')

# Check if GDB security is enabled
if [[ $is_security_enabled == "true" ]]; then
  echo "Security is enabled"
else
  # Set the admin password
  SET_PASSWORD=$(
    curl --location -s -w "%%{http_code}" \
      --request PATCH 'http://localhost:7200/rest/security/users/admin' \
      --header 'Content-Type: application/json' \
      --data "{ \"password\": \"$${GRAPHDB_ADMIN_PASSWORD}\" }"
  )
  if [[ "$SET_PASSWORD" == 200 ]]; then
    echo "Set GraphDB password successfully"
  else
    echo "Failed setting GraphDB password. Please check the logs!"
  fi

  # Enable the security
  ENABLED_SECURITY=$(curl -X POST -s -w "%%{http_code}" \
    --header 'Content-Type: application/json' \
    --header 'Accept: */*' \
    -d 'true' 'http://localhost:7200/rest/security')

  if [[ "$ENABLED_SECURITY" == 200 ]]; then
    echo "Enabled GraphDB security successfully"
  else
    echo "Failed enabling GraphDB security. Please check the logs!"
  fi
fi

echo "###########################"
echo "#    Script completed     #"
echo "###########################"
