#!/bin/bash

# This script focuses on configuring a cron job for GraphDB backup in an Azure environment.
#
# It performs the following tasks:
#   * Sets up a cron job for GraphDB backup using Terraform variables
#   * Writes the cron job configuration to the /etc/cron.d/graphdb_backup file.

set -euo pipefail

echo "#################################################"
echo "#    Configuring the GraphDB backup cron job    #"
echo "#################################################"

cat <<EOF > /usr/bin/run_backup.sh
#!/bin/bash

az login --identity

# Extract GraphDB password from Azure App Configuration
graphdb_password="\$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"

/usr/bin/graphdb_backup admin \$${graphdb_password} ${backup_storage_account_name} ${backup_storage_container_name}

EOF

chmod +x /usr/bin/run_backup.sh
echo "${backup_schedule}" graphdb /usr/bin/run_backup.sh > /etc/cron.d/graphdb_backup

echo "Cron job created"
