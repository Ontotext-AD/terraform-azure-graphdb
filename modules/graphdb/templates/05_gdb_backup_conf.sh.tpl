#!/bin/bash

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

echo "#################################################"
echo "#    Configuring the GraphDB backup cron job    #"
echo "#################################################"

echo "Creating the backup user"
useradd -r -m -s /usr/sbin/nologin gdb-backup || true

# Pre-create the log file so the 'gdb-backup' user can write to it
touch /var/log/graphdb_backup.log
chown gdb-backup:gdb-backup /var/log/graphdb_backup.log
chmod 640 /var/log/graphdb_backup.log

# Configure log rotation for the backup log
cat <<'EOF' >/etc/logrotate.d/graphdb_backup
/var/log/graphdb_backup.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 640 gdb-backup gdb-backup
}
EOF

###############################################################################
# /usr/bin/run_backup.sh
###############################################################################
cat <<'EOF' >/usr/bin/run_backup.sh
#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

LOG_FILE="/var/log/graphdb_backup.log"
exec >>"$LOG_FILE" 2>&1

log_with_timestamp() {
  echo "$(date '+%Y-%m-%d %H:%M:%S'): $*"
}

gdb_get_m2m_token() {
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

storage_account="$${1:?storage account required}"
storage_container="$${2:?storage container required}"

# Rendered by Terraform into THIS template (left as literals inside the quoted heredoc)
app_configuration_endpoint='${app_configuration_endpoint}'
m2m_enabled='${m2m_enabled}'
m2m_client_id='${m2m_client_id}'
m2m_client_secret='${m2m_client_secret}'
m2m_tenant_id='${m2m_tenant_id}'
m2m_scope='${m2m_scope}'

export APP_CONFIGURATION_ENDPOINT="$app_configuration_endpoint"
export M2M_ENABLED="$m2m_enabled"
export M2M_CLIENT_ID="$m2m_client_id"
export M2M_CLIENT_SECRET="$m2m_client_secret"
export M2M_TENANT_ID="$m2m_tenant_id"
export M2M_SCOPE="$m2m_scope"

az login --identity -o none >/dev/null 2>&1 || true

log_with_timestamp "Starting GraphDB backup run for $${storage_account}/$${storage_container}"

verify_container_access() {
  az storage blob list \
    --account-name "$storage_account" \
    --container-name "$storage_container" \
    --auth-mode login \
    --num-results 1 \
    -o none
}

wait_for_blob_to_appear() {
  local tries=18   # ~3 minutes
  local sleep_s=10
  local count

  for i in $(seq 1 "$tries"); do
    # If container is not accessible, fail fast (permissions)
    if ! verify_container_access >/dev/null 2>&1; then
      log_with_timestamp "ERROR: Cannot access container $${storage_account}/$${storage_container} with managed identity."
      return 2
    fi

    count="$(az storage blob list \
      --account-name "$${storage_account}" \
      --container-name "$${storage_container}" \
      --auth-mode login \
      --query "length(@)" -o tsv 2>/dev/null || echo 0)"

    if [[ "$count" != "0" ]]; then
      log_with_timestamp "Upload visible (container blob count: $count)"
      return 0
    fi

    log_with_timestamp "Waiting for backup blob to appear... ($${i}/$${tries})"
    sleep "$sleep_s"
  done

  log_with_timestamp "ERROR: No blobs found after waiting; backup likely not uploaded."
  return 1
}

validate_backup() {
  local rc=0
  local output=""

  # Make execution explicit in logs to avoid "does not run anything" confusion
  log_with_timestamp "Executing: $*"
  output="$("$@" 2>&1)" || rc=$?

  if [[ -n "$${output}" ]]; then
    log_with_timestamp "graphdb_backup output: $${output}"
  fi
  if [[ "$rc" -eq 2 ]]; then
    log_with_timestamp "Node is not the cluster leader; backup skipped on this node."
    return 2
  fi

  if [[ "$rc" -ne 0 ]]; then
    log_with_timestamp "ERROR: graphdb_backup failed with exit code $${rc}"
    return "$${rc}"
  fi

  # GraphDB cloud-backup may be async; wait until something appears in container.
  wait_for_blob_to_appear
}

backup_rc=0
if gdb_backup_auth "$app_configuration_endpoint"; then
  if [[ "$GDB_BACKUP_AUTH_MODE" == "bearer" ]]; then
    log_with_timestamp "Using M2M authentication flow"
    log_with_timestamp "Running graphdb_backup (bearer) for $${storage_account}/$${storage_container}"
    validate_backup /usr/bin/graphdb_backup bearer "$GDB_BACKUP_AUTH_VALUE" "$storage_account" "$storage_container" || backup_rc=$?
  else
    log_with_timestamp "Using basic authentication flow"
    log_with_timestamp "Running graphdb_backup (basic) for $${storage_account}/$${storage_container}"
    validate_backup /usr/bin/graphdb_backup basic admin "$GDB_BACKUP_AUTH_VALUE" "$storage_account" "$storage_container" || backup_rc=$?
  fi
else
  log_with_timestamp "ERROR: Failed to determine backup auth (M2M/basic)"
  exit 1
fi

if [[ "$backup_rc" -eq 2 ]]; then
  exit 0
fi

log_with_timestamp "Backup run completed successfully"
EOF

chmod +x /usr/bin/run_backup.sh

###############################################################################
# /usr/bin/graphdb_backup (override to support bearer tokens)
###############################################################################
cat <<'EOF' >/usr/bin/graphdb_backup
#!/bin/bash

set -euo pipefail

az login --identity >/dev/null 2>&1 || true

mode="$${1:-}"
shift || true

auth_arg1=""
auth_arg2=""
storage_account=""
storage_container=""

if [ "$mode" = "bearer" ]; then
  token="$${1:-}"
  storage_account="$${2:-}"
  storage_container="$${3:-}"
  auth_arg1="-H"
  auth_arg2="Authorization: Bearer $token"
elif [ "$mode" = "basic" ]; then
  user="$${1:-}"
  password="$${2:-}"
  storage_account="$${3:-}"
  storage_container="$${4:-}"
  auth_arg1="-u"
  auth_arg2="$user:$password"
else
  # Backward compatibility: user pass account container
  user="$mode"
  password="$${1:-}"
  storage_account="$${2:-}"
  storage_container="$${3:-}"
  auth_arg1="-u"
  auth_arg2="$user:$password"
fi

backup_name="$(date +'%Y-%m-%d_%H-%M-%S').tar"
max_retries=3
retry_count=0

perform_backup() {
  while [ "$retry_count" -lt "$max_retries" ]; do
    current_time="$(date +"%T %Y-%m-%d")"
    echo "#####################################"
    echo "Begin backup creation $current_time"
    echo "#####################################"
    start_time="$(date +%s)"

    response_code="$(curl -X POST --write-out '%%{http_code}' --silent --output /dev/null \
      --header 'Content-Type: application/json' \
      "$auth_arg1" "$auth_arg2" \
      --header 'Accept: application/json' \
      -d "{\"bucketUri\": \"az://$storage_container/$backup_name?blob_storage_account=$storage_account\", \"backupSystemData\": true}" \
      'http://localhost:7200/rest/recovery/cloud-backup')"

    end_time="$(date +%s)"
    elapsed_time="$((end_time - start_time))"

    if [ "$response_code" -eq 200 ]; then
      echo "Backup uploaded successfully to $storage_account in $elapsed_time seconds."
      break
    else
      echo "Failed to complete the backup and upload. HTTP Response Code: $response_code"
      echo "Request took: $elapsed_time"

      if [ "$retry_count" -eq "$max_retries" ]; then
        echo "Max retries reached. Backup could not be created. Exiting..."
        return 1
      else
        echo "Retrying..."
      fi

      retry_count="$((retry_count + 1))"
      sleep 5
    fi
  done
}

# Checks if GraphDB is running in cluster
is_cluster="$(curl -s -o /dev/null \
  "$auth_arg1" "$auth_arg2" \
  -w "%%{http_code}" \
  http://localhost:7200/rest/monitor/cluster)"

if [ "$is_cluster" = "200" ]; then
  # Only fetch node_state when we know we're in cluster mode (per review comment)
  node_state="$(curl --silent "$auth_arg1" "$auth_arg2" localhost:7200/rest/cluster/node/status | jq -r .nodeState)"

  if [ "$node_state" != "LEADER" ]; then
    echo "The current node is not the leader, but $node_state. Exiting"
    exit 2
  fi
  perform_backup
elif [ "$is_cluster" = "503" ]; then
  perform_backup
fi
EOF

chmod +x /usr/bin/graphdb_backup

###############################################################################
# Cron entry
###############################################################################
cat <<CRONEOF > /etc/cron.d/graphdb_backup
${backup_schedule} gdb-backup /usr/bin/run_backup.sh ${backup_storage_account_name} ${backup_storage_container_name}
CRONEOF

chmod og-rwx /etc/cron.d/graphdb_backup
 # Set ownership of az-cli to backup user
   chown -R gdb-backup:gdb-backup /opt/az /usr/bin/az /opt/microsoft
   chmod -R og-rwx /opt/az /opt/microsoft /usr/bin/az

log_with_timestamp "Cron job created"
