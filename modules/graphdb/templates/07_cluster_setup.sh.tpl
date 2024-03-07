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
#   * Updates the GraphDB admin password if it has been changed in Application Config

set -euo pipefail

echo "###########################"
echo "#    Starting GraphDB     #"
echo "###########################"

INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
DNS_ZONE_NAME=${private_dns_zone_name}
GRAPHDB_ADMIN_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
GRAPHDB_PASSWORD_CREATION_TIME="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .lastModified)"
LOWEST_INSTANCE_ID=$(cat /tmp/lowest_id)
RECORD_NAME=$(cat /tmp/node_name)

# To update the password if changed we need to save the creation date of the config.
# If a file is found, it will treat the password from Application config as the latest and update it.
if [ ! -e "/var/opt/graphdb/password_creation_time" ]; then
  # This has to be persisted
  echo $(date -d "$GRAPHDB_PASSWORD_CREATION_TIME" -u +"%Y-%m-%dT%H:%M:%S") > /var/opt/graphdb/password_creation_time
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

echo "Started GraphDB services"

check_gdb() {
  if [ -z "$1" ]; then
    echo "Error: IP address or hostname is not provided."
    return 1
  fi

  local gdb_address="$1:7200/rest/monitor/infrastructure"
  if curl -s --head -u "admin:$${GRAPHDB_PASSWORD}" --fail "$gdb_address" >/dev/null; then
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

#  Only the instance with the lowest ID would attempt to create the cluster
if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then

  echo "##################################"
  echo "#    Beginning cluster setup     #"
  echo "##################################"

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

  echo "All GDB instances are available. Proceeding..."

  for ((i = 1; i <= $MAX_RETRIES; i++)); do
    IS_CLUSTER=$(
      curl -s -o /dev/null \
        -u "admin:$GRAPHDB_PASSWORD" \
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
          -o "/dev/null" \
          -H 'Content-type: application/json' \
          -u "admin:$${GRAPHDB_PASSWORD}" \
          -d "{\"nodes\": [\"node-1.$${DNS_ZONE_NAME}:7300\",\"node-2.$${DNS_ZONE_NAME}:7300\",\"node-3.$${DNS_ZONE_NAME}:7300\"]}"
      )
      if [[ "$CLUSTER_CREATED" == 201 ]]; then
        echo "GraphDB cluster successfully created!"
        break
      else
        echo "Unexpected Status code returned $CLUSTER_CREATED"
      fi
    elif [ "$IS_CLUSTER" == 200 ]; then
      echo "Cluster exists"
      break
    else
      echo "Something went wrong, returned: $IS_CLUSTER. Check the logs!"
    fi
  done

  # Setting the security should be done on the Leader node only
  echo "###########################################################"
  echo "#    Changing admin user password and enable security     #"
  echo "###########################################################"

  IS_SECURITY_ENABLED=$(curl -s -X GET \
  --header 'Accept: application/json' \
  -u "admin:$${GRAPHDB_PASSWORD}" \
  'http://localhost:7200/rest/security')

  # Check if GDB security is enabled
  if [[ $IS_SECURITY_ENABLED == "true" ]]; then
    echo "Security is enabled"
  else
    # Set the admin password
    SET_PASSWORD=$(
      curl --location -s -w "%%{http_code}" \
        --request PATCH 'http://localhost:7200/rest/security/users/admin' \
        --header 'Content-Type: application/json' \
        --data "{ \"password\": \"$${GRAPHDB_PASSWORD}\" }"
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
else
  echo "The current instance: $INSTANCE_ID is not the lowest, skipping cluster creation"
fi

echo "####################################"
echo "#    Updating GraphDB password     #"
echo "####################################"

# This will update the GraphDB admin password if this node has the lowest ID and password_creation_time file exists.
if [[ -e "/var/opt/graphdb/password_creation_time" && "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]]; then
    # The request will fail if the cluster state is unhealthy
    # This handles rolling updates
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

    # Gets the existing settings for admin user
    EXISTING_SETTINGS=$(curl --location -s -u "admin:$${GRAPHDB_PASSWORD}" 'http://localhost:7200/rest/security/users/admin' | jq -rc '{grantedAuthorities, appSettings}' | sed 's/^{//;s/}$//')

    SET_NEW_PASSWORD=$(
      curl --location -s -w "%%{http_code}" \
        --request PATCH 'http://localhost:7200/rest/security/users/admin' \
        --header 'Content-Type: application/json' \
        --header 'Accept: text/plain' \
        -u "admin:$${GRAPHDB_PASSWORD}" \
        --data "{\"password\":\"$${GRAPHDB_ADMIN_PASSWORD}\",$EXISTING_SETTINGS}"
    )
    if [[ "$SET_NEW_PASSWORD" == 200 ]]; then
      echo "Updated GraphDB password successfully"
      GRAPHDB_PASSWORD_CREATION_TIME="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .lastModified)"
      echo $(date -d "$GRAPHDB_PASSWORD_CREATION_TIME" -u +"%Y-%m-%dT%H:%M:%S") >/var/opt/graphdb/password_creation_time
    else
      echo "Failed updating GraphDB password. Please check the logs!"
      exit 1
    fi
else
  echo "The current instance: $INSTANCE_ID is not the lowest, skipping password update"
fi
