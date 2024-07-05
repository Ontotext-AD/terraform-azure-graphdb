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
