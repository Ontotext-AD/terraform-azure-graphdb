#!/bin/bash

# This script focuses on configuring a cron job for GraphDB backup in an Azure environment.
#
# It performs the following tasks:
#   * Sets up a cron job for GraphDB backup using Terraform variables
#   * Writes the cron job configuration to the /etc/cron.d/graphdb_backup file.

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

echo "#################################################"
echo "#    Configuring the GraphDB backup cron job    #"
echo "#################################################"

echo "Creating the backup user"
echo "Creating the backup user"
useradd -r -m -s /usr/sbin/nologin gdb-backup

cat <<EOF >/usr/bin/run_backup.sh
#!/bin/bash

storage_account="\$1"
storage_container="\$2"

az login --identity

# Extract GraphDB password from Azure App Configuration
graphdb_password="\$(az appconfig kv show \
  --endpoint ${app_configuration_endpoint} \
  --auth-mode login \
  --key graphdb-password \
  | jq -r .value \
  | base64 -d)"

/usr/bin/graphdb_backup admin "\$${graphdb_password}" "\$${storage_account}" "\$${storage_container}"

EOF

chmod +x /usr/bin/run_backup.sh
echo "${backup_schedule} gdb-backup /usr/bin/run_backup.sh ${backup_storage_account_name} ${backup_storage_container_name}" > /etc/cron.d/graphdb_backup
chmod og-rwx /etc/cron.d/graphdb_backup
# Set ownership of az-cli to backup user
  chown -R gdb-backup:gdb-backup /opt/az /usr/bin/az /opt/microsoft
  chmod -R og-rwx /opt/az /opt/microsoft /usr/bin/az
log_with_timestamp "Cron job created"
