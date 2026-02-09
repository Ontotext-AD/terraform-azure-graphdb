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

# Initialize GraphDB auth args. Uses M2M when enabled and available, otherwise falls back to basic auth.
gdb_get_m2m_token() {
  # Treat "null" as unset.
  local client_id="$${M2M_CLIENT_ID:-}"
  local client_secret="$${M2M_CLIENT_SECRET:-}"
  local tenant_id="$${M2M_TENANT_ID:-}"
  local scope="$${M2M_SCOPE:-}"

  if [[ -z "$${client_id}" || "$${client_id}" == "null" ]]; then
    log_with_timestamp "M2M: missing M2M_CLIENT_ID; falling back to basic auth"
    return 1
  fi

  if [[ -z "$${client_secret}" || "$${client_secret}" == "null" ]]; then
    log_with_timestamp "M2M: missing M2M_CLIENT_SECRET; falling back to basic auth"
    return 1
  fi

  if [[ -z "$${tenant_id}" || "$${tenant_id}" == "null" ]]; then
    log_with_timestamp "M2M: missing M2M_TENANT_ID; falling back to basic auth"
    return 1
  fi

  # Scope can be provided directly or fetched from AppConfig
  if [[ -z "$${scope}" || "$${scope}" == "null" ]]; then
    if [[ -n "$${APP_CONFIGURATION_ENDPOINT:-}" && "$${APP_CONFIGURATION_ENDPOINT}" != "null" ]]; then
      az login --identity -o none >/dev/null 2>&1 || true
      scope="$(az appconfig kv show \
        --endpoint "$${APP_CONFIGURATION_ENDPOINT}" \
        --auth-mode login \
        --key m2m-app-scope \
        --query value -o tsv 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$${scope}" || "$${scope}" == "null" ]]; then
    log_with_timestamp "M2M: missing scope (M2M_SCOPE or AppConfig key m2m-app-scope); falling back to basic auth"
    return 1
  fi

  local token_response
  token_response="$(curl -sS -X POST "https://login.microsoftonline.com/$${tenant_id}/oauth2/v2.0/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=$${client_id}" \
    --data-urlencode "client_secret=$${client_secret}" \
    --data-urlencode "scope=$${scope}" \
    --data-urlencode "grant_type=client_credentials" 2>/dev/null || true)"

  local token
  token="$(echo "$${token_response}" | jq -r '.access_token // empty' 2>/dev/null || true)"

  if [[ -z "$${token}" ]]; then
    # Log Azure AD error if present (no secrets)
    local err desc
    err="$(echo "$${token_response}" | jq -r '.error // empty' 2>/dev/null || true)"
    desc="$(echo "$${token_response}" | jq -r '.error_description // empty' 2>/dev/null || true)"
    if [[ -n "$${err}" || -n "$${desc}" ]]; then
      log_with_timestamp "M2M: token request failed ($${err:-unknown}): $${desc:-no description}"
    else
      log_with_timestamp "M2M: token request failed (no access_token in response)"
    fi
    return 1
  fi

  printf '%s' "$${token}"
}

gdb_init_auth() {
  GDB_BEARER_TOKEN=""
  if [[ "$${M2M_ENABLED:-false}" == "true" ]]; then
    local token
    token="$(gdb_get_m2m_token || true)"
    if [[ -n "$${token}" && "$${token}" != "null" ]]; then
      GDB_BEARER_TOKEN="$${token}"
      log_with_timestamp "M2M: bearer token acquired; will use bearer auth"
    else
      log_with_timestamp "M2M: enabled but token not available; will fall back to basic auth"
    fi
  fi
}

gdb_curl() {
  # Use bearer only when TF enables M2M AND we actually have a token
  if [[ "$${M2M_ENABLED:-false}" == "true" && -n "$GDB_BEARER_TOKEN" ]]; then
    if curl "$@" -H "Authorization: Bearer $GDB_BEARER_TOKEN"; then
      return 0
    fi
    log_with_timestamp "Bearer auth failed; falling back to basic"
  fi

  if [[ -z "$${GRAPHDB_PASSWORD:-}" ]]; then
    log_with_timestamp "GraphDB password not set; basic auth disabled"
    return 1
  fi

  curl "$@" -u "admin:$${GRAPHDB_PASSWORD}"
}

configure_graphdb_security_basic() {
  local GRAPHDB_PASSWORD="$1"
  local GRAPHDB_URL=$${2:-"http://localhost:7200"}

  IS_SECURITY_ENABLED=$(curl -s -X GET \
    --header 'Accept: application/json' \
    -u "admin:$${GRAPHDB_PASSWORD}" \
    "$${GRAPHDB_URL}/rest/security")

  if [[ $IS_SECURITY_ENABLED == "true" ]]; then
    log_with_timestamp "Security is enabled"
  else
    SET_PASSWORD=$(
      curl --location -s -w "%%{http_code}" \
        --request PATCH "$${GRAPHDB_URL}/rest/security/users/admin" \
        --header 'Content-Type: application/json' \
        -u "admin:$${GRAPHDB_PASSWORD}" \
        --data "{ \"password\": \"$GRAPHDB_PASSWORD\" }"
    )
    if [[ "$SET_PASSWORD" == 200 ]]; then
      log_with_timestamp "Set GraphDB password successfully"
    else
      log_with_timestamp "Failed setting GraphDB password. Please check the logs!"
    fi

    ENABLED_SECURITY=$(curl -X POST -s -w "%%{http_code}" \
      --header 'Content-Type: application/json' \
      --header 'Accept: */*' \
      -u "admin:$${GRAPHDB_PASSWORD}" \
      -d 'true' "$${GRAPHDB_URL}/rest/security")

    if [[ "$ENABLED_SECURITY" == 200 ]]; then
      log_with_timestamp "Enabled GraphDB security successfully"
    else
      log_with_timestamp "Failed enabling GraphDB security. Please check the logs!"
    fi
  fi
}

# Determine backup auth mode and value.
# Sets:
#   GDB_BACKUP_AUTH_MODE: "bearer" or "basic"
#   GDB_BACKUP_AUTH_VALUE: token or password
gdb_backup_auth() {
  local app_config_endpoint="$1"
  GDB_BACKUP_AUTH_MODE="basic"
  GDB_BACKUP_AUTH_VALUE=""

  if [[ "$${M2M_ENABLED:-false}" == "true" ]]; then
    local token
    token="$(gdb_get_m2m_token || true)"
    if [[ -n "$${token}" && "$${token}" != "null" ]]; then
      GDB_BACKUP_AUTH_MODE="bearer"
      GDB_BACKUP_AUTH_VALUE="$${token}"
      return 0
    fi
    log_with_timestamp "M2M: enabled but token not available for backup; falling back to basic auth"
  fi

  local pwd
  pwd="$(az appconfig kv show \
    --endpoint "$${app_config_endpoint}" \
    --auth-mode login \
    --key graphdb-password \
    --query value -o tsv | base64 -d)"

  if [[ -z "$pwd" ]]; then
    log_with_timestamp "Backup auth: failed to fetch graphdb-password from AppConfig"
    return 1
  fi

  GDB_BACKUP_AUTH_VALUE="$pwd"
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
    RUNNING_NODE_COUNT=$(az vmss list-instances \
                           --resource-group "$RESOURCE_GROUP" \
                           --name "$VMSS_NAME" \
                           --expand instanceView \
                           --query "[?instanceView.statuses[?code=='PowerState/running']].instanceId" \
                           --output tsv | wc -l)

    DELETING_NODE_COUNT=$(az vmss list-instances \
                            --resource-group "$RESOURCE_GROUP" \
                            --name "$VMSS_NAME" \
                            --query "[?provisioningState=='Deleting'].instanceId" \
                            --output tsv | wc -l)

    echo "Running: $RUNNING_NODE_COUNT, Deleting: $DELETING_NODE_COUNT, Desired: $NODE_COUNT"

    if [[ "$RUNNING_NODE_COUNT" -ne "$NODE_COUNT" ]] && [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
      echo "Error: Running nodes count ($RUNNING_NODE_COUNT) does not match the desired node count ($NODE_COUNT) after $MAX_RETRIES retries. Exiting..."
      exit 1
    fi

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
  if gdb_curl -s --head --fail "$gdb_address" >/dev/null; then
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
    cleanedAddress=$${record%?}
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
  IS_SECURITY_ENABLED=$(gdb_curl -s -X GET \
    --header 'Accept: application/json' \
    "$${GRAPHDB_URL}/rest/security")

  if [[ $IS_SECURITY_ENABLED == "true" ]]; then
    log_with_timestamp "Security is enabled"
  else
    SET_PASSWORD=$(
      gdb_curl --location -s -w "%%{http_code}" \
        --request PATCH "$${GRAPHDB_URL}/rest/security/users/admin" \
        --header 'Content-Type: application/json' \
        --data "{ \"password\": \"$GRAPHDB_PASSWORD\" }"
    )
    if [[ "$SET_PASSWORD" == 200 ]]; then
      log_with_timestamp "Set GraphDB password successfully"
    else
      log_with_timestamp "Failed setting GraphDB password. Please check the logs!"
    fi

    ENABLED_SECURITY=$(gdb_curl -X POST -s -w "%%{http_code}" \
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
  if [[ "$${M2M_ENABLED:-false}" == "true" ]]; then
    log_with_timestamp "M2M enabled; skipping GraphDB password update (single node)"
    return 0
  fi
  if [[ -e "/var/opt/graphdb/password_creation_time" ]]; then
    EXISTING_SETTINGS=$(gdb_curl --location -s 'http://localhost:7200/rest/security/users/admin' | jq -rc '{grantedAuthorities, appSettings}' | sed 's/^{//;s/}$//')

    SET_NEW_PASSWORD=$(
      gdb_curl --location -s -w "%%{http_code}" \
        --request PATCH 'http://localhost:7200/rest/security/users/admin' \
        --header 'Content-Type: application/json' \
        --header 'Accept: text/plain' \
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
  if [[ "$${M2M_ENABLED:-false}" == "true" ]]; then
    log_with_timestamp "M2M enabled; skipping GraphDB password update (cluster)"
    return 0
  fi
  if [[ -e "/var/opt/graphdb/password_creation_time" ]]; then
    readarray -t ALL_DNS_RECORDS <<<"$(az network private-dns record-set list \
      --zone "$DNS_ZONE_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --query '[?contains(name, '\''node'\'')].fqdn' \
      --output tsv
    )"
    for record in "$${ALL_DNS_RECORDS[@]}"; do
      log_with_timestamp "Pinging $record"
      cleanedAddress=$${record%?}
      if [ -n "$cleanedAddress" ]; then
        while ! check_gdb "$cleanedAddress"; do
          log_with_timestamp "Waiting for GDB $cleanedAddress to start"
          sleep "$RETRY_DELAY"
        done
      else
        log_with_timestamp "Error: cleanedAddress is empty."
      fi
    done

    EXISTING_SETTINGS=$(gdb_curl --location -s 'http://localhost:7200/rest/security/users/admin' | jq -rc '{grantedAuthorities, appSettings}' | sed 's/^{//;s/}$//')

    SET_NEW_PASSWORD=$(
      gdb_curl --location -s -w "%%{http_code}" \
        --request PATCH 'http://localhost:7200/rest/security/users/admin' \
        --header 'Content-Type: application/json' \
        --header 'Accept: text/plain' \
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
