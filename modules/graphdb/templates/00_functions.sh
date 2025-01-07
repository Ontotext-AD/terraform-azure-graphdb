#!/usr/bin/env bash

# Generic helper functions

# Function to print messages with timestamps
log_with_timestamp() {
  if [ -z "$1" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ERROR: Missing log message" >&2
    return 1
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}

wait_for_vmss_nodes() {
  local VMSS_NAME="$1"
  local RESOURCE_GROUP="$2"
  local RETRY_DELAY=10
  local MAX_RETRIES=65
  local RETRY_COUNT=0

  # Get the desired capacity of the VMSS
  local NODE_COUNT
  NODE_COUNT=$(az vmss show \
               --name "$VMSS_NAME" \
               --resource-group "$RESOURCE_GROUP" \
               --query "sku.capacity" \
               --output tsv)

  # Check if NODE_COUNT is numeric and greater than 0
  if [ "$NODE_COUNT" -eq "$NODE_COUNT" ] 2>/dev/null && [ "$NODE_COUNT" -ge 0 ]; then
    echo "Node count is valid: $NODE_COUNT"
  else
    echo "Invalid node count: $NODE_COUNT"
    exit 1
  fi

  echo "Checking VMSS node count for $VMSS_NAME with desired node count: $NODE_COUNT"

  while true; do
    # Get the count of running instances
    RUNNING_NODE_COUNT=$(az vmss list-instances \
                           --resource-group "$RESOURCE_GROUP" \
                           --name "$VMSS_NAME" \
                           --expand instanceView \
                           --query "[?instanceView.statuses[?code=='PowerState/running']].instanceId" \
                           --output tsv | wc -l)

    # Get the count of deleting instances
    DELETING_NODE_COUNT=$(az vmss list-instances \
                            --resource-group "$RESOURCE_GROUP" \
                            --name "$VMSS_NAME" \
                            --query "[?provisioningState=='Deleting'].instanceId" \
                            --output tsv | wc -l)

    echo "Running: $RUNNING_NODE_COUNT, Deleting: $DELETING_NODE_COUNT, Desired: $NODE_COUNT"

    # Validate conditions: If retry count is exhausted
    if [[ "$RUNNING_NODE_COUNT" -ne "$NODE_COUNT" ]] && [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
      echo "Error: Running nodes count ($RUNNING_NODE_COUNT) does not match the desired node count ($NODE_COUNT) after $MAX_RETRIES retries. Exiting..."
      exit 1
    fi

    # If the conditions are met, break out of the loop
    if [[ "$RUNNING_NODE_COUNT" -ge "$NODE_COUNT" ]] && [[ "$DELETING_NODE_COUNT" -eq 0 ]]; then
      echo "Conditions met: Running instances >= $NODE_COUNT, no Deleting instances. Proceeding..."
      break
    else
      if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        echo "Error: Maximum retry attempts reached. Exiting..."
        exit 1
      fi

      echo "Conditions not met. Waiting... (Running: $RUNNING_NODE_COUNT, Deleting: $DELETING_NODE_COUNT)"
      sleep "$RETRY_DELAY"
      RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
  done
}

check_gdb() {
  if [ -z "$1" ]; then
    log_with_timestamp "Error: IP address or hostname is not provided."
    return 1
  fi

  local gdb_address="$1:7200/rest/monitor/infrastructure"
  if curl -s --head -u "admin:$${GRAPHDB_PASSWORD}" --fail "$gdb_address" >/dev/null; then
    log_with_timestamp "Success, GraphDB node $gdb_address is available"
    return 0
  else
    log_with_timestamp "GraphDB node $gdb_address is not available yet"
    return 1
  fi
}

check_all_dns_records() {
  local DNS_ZONE_NAME="$1"
  local RESOURCE_GROUP="$2"
  local RETRY_DELAY="$3"

  readarray -t ALL_DNS_RECORDS <<<"$(az network private-dns record-set list \
    --zone "$DNS_ZONE_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query '[?contains(name, '\''node'\'')].fqdn' \
    --output tsv
  )"

  for record in "$${ALL_DNS_RECORDS[@]}"; do
    log_with_timestamp "Pinging $record"
    # Removes the '.' at the end of the DNS address
    cleanedAddress=$${record%?}
    # Check if cleanedAddress is non-empty before calling check_gdb
    if [ -n "$cleanedAddress" ]; then
      while ! check_gdb "$cleanedAddress"; do
        log_with_timestamp "Waiting for GDB $cleanedAddress to start"
        sleep "$RETRY_DELAY"
      done
    else
      log_with_timestamp "Error: cleanedAddress is empty."
    fi
  done

  log_with_timestamp "All GDB instances are available. Proceeding..."
}

configure_graphdb_security() {
  local GRAPHDB_PASSWORD=$1
  local GRAPHDB_URL=$${2:-"http://localhost:7200"}

  IS_SECURITY_ENABLED=$(curl -s -X GET \
    --header 'Accept: application/json' \
    -u "admin:$GRAPHDB_PASSWORD" \
    "$${GRAPHDB_URL}/rest/security")

  # Check if GDB security is enabled
  if [[ $IS_SECURITY_ENABLED == "true" ]]; then
    log_with_timestamp "Security is enabled"
  else
    # Set the admin password
    SET_PASSWORD=$(
      curl --location -s -w "%%{http_code}" \
        --request PATCH "$${GRAPHDB_URL}/rest/security/users/admin" \
        --header 'Content-Type: application/json' \
        --data "{ \"password\": \"$GRAPHDB_PASSWORD\" }"
    )
    if [[ "$SET_PASSWORD" == 200 ]]; then
      log_with_timestamp "Set GraphDB password successfully"
    else
      log_with_timestamp "Failed setting GraphDB password. Please check the logs!"
    fi

    # Enable the security
    ENABLED_SECURITY=$(curl -X POST -s -w "%%{http_code}" \
      --header 'Content-Type: application/json' \
      --header 'Accept: */*' \
      -d 'true' "$${GRAPHDB_URL}/rest/security")

    if [[ "$ENABLED_SECURITY" == 200 ]]; then
      log_with_timestamp "Enabled GraphDB security successfully"
    else
      log_with_timestamp "Failed enabling GraphDB security. Please check the logs!"
    fi
  fi
}

update_graphdb_admin_password_single_node() {
  local GRAPHDB_PASSWORD="$1"
  local GRAPHDB_ADMIN_PASSWORD="$2"
  local RETRY_DELAY="$3"
  local APP_CONFIGURATION_ENDPOINT="$4"

  if [[ -e "/var/opt/graphdb/password_creation_time" ]]; then
    # Gets the existing settings for admin user
    EXISTING_SETTINGS=$(curl --location -s -u "admin:$GRAPHDB_PASSWORD" 'http://localhost:7200/rest/security/users/admin' | jq -rc '{grantedAuthorities, appSettings}' | sed 's/^{//;s/}$//')

    SET_NEW_PASSWORD=$(
      curl --location -s -w "%%{http_code}" \
        --request PATCH 'http://localhost:7200/rest/security/users/admin' \
        --header 'Content-Type: application/json' \
        --header 'Accept: text/plain' \
        -u "admin:$GRAPHDB_PASSWORD" \
        --data "{\"password\":\"$GRAPHDB_ADMIN_PASSWORD\",$EXISTING_SETTINGS}"
    )
    if [[ "$SET_NEW_PASSWORD" == 200 ]]; then
      log_with_timestamp "Updated GraphDB password successfully"
      GRAPHDB_PASSWORD_CREATION_TIME="$(az appconfig kv show --endpoint $${APP_CONFIGURATION_ENDPOINT} --auth-mode login --key graphdb-password | jq -r .lastModified)"
      echo $(date -d "$GRAPHDB_PASSWORD_CREATION_TIME" -u +"%Y-%m-%dT%H:%M:%S") > /var/opt/graphdb/password_creation_time
    else
      log_with_timestamp "Failed updating GraphDB password. Please check the logs!"
      exit 1
    fi
  fi
}

update_graphdb_admin_password() {
  local GRAPHDB_PASSWORD="$1"
  local GRAPHDB_ADMIN_PASSWORD="$2"
  local RETRY_DELAY="$3"
  local APP_CONFIGURATION_ENDPOINT="$4"

  if [[ -e "/var/opt/graphdb/password_creation_time" ]]; then
    # The request will fail if the cluster state is unhealthy
    # This handles rolling updates
    readarray -t ALL_DNS_RECORDS <<<"$(az network private-dns record-set list \
      --zone "$DNS_ZONE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query '[?contains(name, '\''node'\'')].fqdn' \
      --output tsv
    )"
    for record in "$${ALL_DNS_RECORDS[@]}"; do
      log_with_timestamp "Pinging $record"
      # Removes the '.' at the end of the DNS address
      cleanedAddress=$${record%?}
      # Check if cleanedAddress is non-empty before calling check_gdb
      if [ -n "$cleanedAddress" ]; then
        while ! check_gdb "$cleanedAddress"; do
          log_with_timestamp "Waiting for GDB $cleanedAddress to start"
          sleep "$RETRY_DELAY"
        done
      else
        log_with_timestamp "Error: cleanedAddress is empty."
      fi
    done

    # Gets the existing settings for admin user
    EXISTING_SETTINGS=$(curl --location -s -u "admin:$GRAPHDB_PASSWORD" 'http://localhost:7200/rest/security/users/admin' | jq -rc '{grantedAuthorities, appSettings}' | sed 's/^{//;s/}$//')

    SET_NEW_PASSWORD=$(
      curl --location -s -w "%%{http_code}" \
        --request PATCH 'http://localhost:7200/rest/security/users/admin' \
        --header 'Content-Type: application/json' \
        --header 'Accept: text/plain' \
        -u "admin:$GRAPHDB_PASSWORD" \
        --data "{\"password\":\"$GRAPHDB_ADMIN_PASSWORD\",$EXISTING_SETTINGS}"
    )
    if [[ "$SET_NEW_PASSWORD" == 200 ]]; then
      log_with_timestamp "Updated GraphDB password successfully"
      GRAPHDB_PASSWORD_CREATION_TIME="$(az appconfig kv show --endpoint $${APP_CONFIGURATION_ENDPOINT} --auth-mode login --key graphdb-password | jq -r .lastModified)"
      echo $(date -d "$GRAPHDB_PASSWORD_CREATION_TIME" -u +"%Y-%m-%dT%H:%M:%S") > /var/opt/graphdb/password_creation_time
    else
      log_with_timestamp "Failed updating GraphDB password. Please check the logs!"
      exit 1
    fi
  fi
}

wait_dns_records() {
  local DNS_ZONE_NAME="$1"
  local RESOURCE_GROUP="$2"
  local NODE_COUNT="$3"

  ALL_FQDN_RECORDS_COUNT=($(
    az network private-dns record-set list \
      --zone $DNS_ZONE_NAME \
      --resource-group $RESOURCE_GROUP \
      --query "[?contains(name, 'node')].fqdn | length(@)"
  ))

  if [ "$${ALL_FQDN_RECORDS_COUNT}" -ne "$NODE_COUNT" ]; then
    log_with_timestamp "Expected $NODE_COUNT, found $${ALL_FQDN_RECORDS_COUNT}"
    sleep 5
    wait_dns_records "$DNS_ZONE_NAME" "$RESOURCE_GROUP" "$NODE_COUNT"
  else
    log_with_timestamp "Private DNS zone record count is $${ALL_FQDN_RECORDS_COUNT}"
  fi
}
