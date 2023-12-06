#!/bin/bash

# Configure the GraphDB backup cron job

cat <<-EOF > /usr/bin/graphdb_backup
#!/bin/bash

set -euxo pipefail

az login --identity

RESOURCE_GROUP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
GRAPHDB_ADMIN_PASSWORD="$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-password --query "value" --output tsv)"
NODE_STATE="$(curl --silent --fail --user "admin:\$GRAPHDB_ADMIN_PASSWORD" localhost:7200/rest/cluster/node/status | jq -r .nodeState)"

if [ "$NODE_STATE" != "LEADER" ]; then
  echo "current node is not a leader, but $NODE_STATE"
  exit 0
fi

BACKUP_NAME="$(date +'%Y-%m-%d_%H-%M-%S').tar"
MAX_RETRIES=3
RETRY_COUNT=0

while [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
  START_TIME=$(date +%s)

  RESPONSE_CODE=$(curl -X POST --write-out %%{http_code} --silent --output /dev/null \
    --header 'Content-Type: application/json' \
    -u "admin:$GRAPHDB_ADMIN_PASSWORD" \
    --header 'Accept: application/json' \
    -d "{\"bucketUri\": \"az://${backup_storage_container_name}/\$${BACKUP_NAME}?blob_storage_account=${backup_storage_account_name}\", \"backupOptions\": {\"backupSystemData\": true}}" \
    'http://localhost:7200/rest/recovery/cloud-backup'
  )

  END_TIME=$(date +%s)
  ELAPSED_TIME=$((END_TIME - START_TIME))

  if [ "$RESPONSE_CODE" -eq 200 ]; then
    echo "Backup and upload completed successfully in $ELAPSED_TIME seconds."
    break
  else
    echo "Failed to complete the backup and upload. HTTP Response Code: $RESPONSE_CODE"
    echo "Retrying..."

    if [ "$RETRY_COUNT" -eq "$MAX_RETRIES" ]; then
      echo "Max retries reached. Backup could not be created. Exiting..."
    fi

    ((RETRY_COUNT=RETRY_COUNT + 1))
    sleep 5
  fi
done

EOF

chmod +x /usr/bin/graphdb_backup
echo "${backup_schedule} graphdb /usr/bin/graphdb_backup" > /etc/cron.d/graphdb_backup

