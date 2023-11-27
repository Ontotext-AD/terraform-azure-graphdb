#!/usr/bin/env bash

set -euxo pipefail

echo "Configuring GraphDB instance"

# Stop in order to override configurations
systemctl stop graphdb

# Login in Azure CLI with managed identity (user or system assigned)
az login --identity

# Find/create/attach volumes
INSTANCE_HOSTNAME=\'$(hostname)\'
SUBSCRIPTION_ID=$(az account show --query "id" --output tsv)
RESOURCE_GROUP=$(az vmss list --query "[0].resourceGroup" --output tsv)
VMSS_NAME=$(az vmss list --query "[0].name" --output tsv)
INSTANCE_ID=$(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[?contains(osProfile.computerName, $${INSTANCE_HOSTNAME})].instanceId" --output tsv)
ZONE_ID=$(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[?contains(osProfile.computerName, $${INSTANCE_HOSTNAME})].zones" --output tsv)
REGION_ID=$(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[?contains(osProfile.computerName, $${INSTANCE_HOSTNAME})].location" --output tsv)
# Do NOT change the LUN. Based on this we find and mount the disk in the VM
LUN=2

DISK_IOPS=${disk_iops_read_write}
DISK_THROUGHPUT=${disk_mbps_read_write}
DISK_SIZE_GB=${disk_size_gb}

for i in $(seq 1 6); do
# Wait for existing disks in the VMSS which are unattached
existingUnattachedDisk=$(
  az disk list --resource-group $RESOURCE_GROUP \
    --query "[?diskState=='Unattached' && starts_with(name, 'Disk-$${RESOURCE_GROUP}') && zones[0]=='$${ZONE_ID}'].{Name:name}" \
    --output tsv
  )

  if [ -z "$${existingUnattachedDisk:-}" ]; then
    echo 'Disk not yet available'
    sleep 10
  else
    break
  fi
done

if [ -z "$existingUnattachedDisk" ]; then
  echo "Creating a new managed disk"
  # Fetch the number of elements
  numElements=$(az disk list --query "length([?zones[0]=='$${ZONE_ID}'])" --output tsv)

  # Increment the number for the new name
  DISK_ORDER=$((numElements + 1))

  # TODO Define the disk name based on the hostname ??
  diskName="Disk-$${RESOURCE_GROUP}-$${ZONE_ID}-$${DISK_ORDER}"

  az disk create --resource-group $RESOURCE_GROUP \
   --name $diskName \
   --size-gb $DISK_SIZE_GB \
   --location $REGION_ID \
   --sku PremiumV2_LRS \
   --zone $ZONE_ID \
   --os-type Linux \
   --disk-iops-read-write $DISK_IOPS \
   --disk-mbps-read-write $DISK_THROUGHPUT \
   --tags createdBy=$INSTANCE_HOSTNAME \
   --public-network-access Disabled \
   --network-access-policy DenyAll
fi

# Checks if a managed disk is attached to the instance
attachedDisk=$(az vmss list-instances --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" --query "[?instanceId==\"$INSTANCE_ID\"].storageProfile.dataDisks[].name" --output tsv)

if [ -z "$attachedDisk" ]; then
    echo "No data disks attached for instance ID $INSTANCE_ID in VMSS $VMSS_NAME."
    # Try to attach an existing managed disk
    availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'Disk-$${RESOURCE_GROUP}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)
    echo "Attaching available disk $availableDisks."
    # Set Internal Field Separator to newline to handle spaces in names
    IFS=$'\n'
    # Would iterate through all available disks and attempt to attach them
    for availableDisk in $availableDisks; do
      az vmss disk attach --vmss-name $VMSS_NAME --resource-group $RESOURCE_GROUP --instance-id $INSTANCE_ID --lun $LUN --disk "$availableDisk" || true
    done
fi

# Gets device name based on LUN
graphdb_device=$(lsscsi --scsi --size | awk '/\[1:.*:0:2\]/ {print $7}')

# Check if the device is present after attaching the disk
if [ -b "$graphdb_device" ]; then
    echo "Device $graphdb_device is available."
else
    echo "Device $graphdb_device is not available. Something went wrong."
    exit 1
fi

# create a file system if there isn't any
if [ "$graphdb_device: data" = "$(file -s $graphdb_device)" ]; then
  mkfs -t ext4 $graphdb_device
fi

disk_mount_point="/var/opt/graphdb"
mkdir -p "$disk_mount_point"

# Check if the disk is already mounted
if ! mount | grep -q "$graphdb_device"; then
  echo "The disk at $graphdb_device is not mounted."

  # Add an entry to the fstab file to automatically mount the disk
  if ! grep -q "$graphdb_device" /etc/fstab; then
    echo "$graphdb_device $disk_mount_point ext4 defaults 0 2" >> /etc/fstab
  fi

  # Mount the disk
  mount "$disk_mount_point"
  echo "The disk at $graphdb_device is now mounted at $disk_mount_point."
else
  echo "The disk at $graphdb_device is already mounted."
fi

# Recreates folders if necessary and changes owner

mkdir -p /var/opt/graphdb/node /var/opt/graphdb/cluster-proxy
# TODO research how to avoid using chown, as it would be a slow operation if data is present.
chown -R graphdb:graphdb /var/opt/graphdb

#
# DNS hack
#

# TODO This won't handle cases where we have 2 VMs in 1 AZ. Since we cannot change the computerName when in VMSS our hands are tied

ZONE_NAME=$(az network private-dns zone list --query "[].name" --output tsv)
IP_ADDRESS=$(hostname -I | xargs)
VMSS_INSTANCE_NAME=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-01-01&format=text")
ATTACHED_DISK_NAME=$(az disk list --query "[?diskState == 'Attached' && contains(managedBy, '$${VMSS_INSTANCE_NAME}')].name" --output tsv)
RECORD_NAME="$( echo -n "$ATTACHED_DISK_NAME" | sed 's/^Disk/Node/' )"

EXISTING_DNS_RECORD=$(az network private-dns record-set a show --resource-group $RESOURCE_GROUP --zone-name $ZONE_NAME --name $RECORD_NAME --output json) || EXISTING_DNS_RECORD=""

  if [ -z "$EXISTING_DNS_RECORD" ]; then
      echo "Creating a new DNS record..."
      az network private-dns record-set a add-record --resource-group $RESOURCE_GROUP --zone-name $ZONE_NAME --record-set-name $RECORD_NAME --ipv4-address "$IP_ADDRESS"
      echo "DNS record created successfully."
  else
      echo "Updating existing DNS record..."
      az network private-dns record-set a update --resource-group $RESOURCE_GROUP --zone-name $ZONE_NAME --name $RECORD_NAME --set ARecords[0].ipv4Address="$IP_ADDRESS"
      echo "DNS record updated successfully."
  fi

# Gets the full DNS record for the current instance
node_dns=$(az network private-dns record-set a show --resource-group $RESOURCE_GROUP --zone-name $ZONE_NAME --name $RECORD_NAME --output tsv --query "fqdn" | rev | cut -c 2- | rev)

#
# GraphDB configuration overrides
#

secrets=$(az keyvault secret list --vault-name ${key_vault_name} --output json | jq .[].name)

# Get the license
az keyvault secret download --vault-name ${key_vault_name} --name graphdb-license --file /etc/graphdb/graphdb.license --encoding base64

# Get the cluster token
graphdb_cluster_token=$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-cluster-token | jq -rj .value | base64 -d)

# TODO: where is the vhost here?
cat << EOF > /etc/graphdb/graphdb.properties
graphdb.auth.token.secret=$graphdb_cluster_token
graphdb.connector.port=7200
graphdb.external-url=http://$${node_dns}:7200/
graphdb.rpc.address=$${node_dns}:7300
EOF

cat << EOF > /etc/graphdb-cluster-proxy/graphdb.properties
graphdb.auth.token.secret=$graphdb_cluster_token
graphdb.connector.port=7201
graphdb.external-url=https://${graphdb_external_address_fqdn}
graphdb.vhosts=https://${graphdb_external_address_fqdn},http://$${node_dns}:7201
graphdb.rpc.address=$${node_dns}:7301
graphdb.proxy.hosts=$${node_dns}:7300
EOF

# Get total memory in kilobytes
total_memory_kb=$(grep -i "MemTotal" /proc/meminfo | awk '{print $2}')

# Convert total memory to gigabytes
total_memory_gb=$(echo "scale=2; $total_memory_kb / 1024 / 1024" | bc)

# Calculate 85% of total memory
jvm_max_memory=$(echo "$total_memory_gb * 0.85" | bc | cut -d'.' -f1)

mkdir -p /etc/systemd/system/graphdb.service.d/

cat << EOF > /etc/systemd/system/graphdb.service.d/overrides.conf
[Service]
Environment="GDB_HEAP_SIZE=$${jvm_max_memory}g"
EOF

# TODO: overrides for the proxy?
# Appends configuration overrides to graphdb.properties
if [[ $secrets == *"graphdb-properties"* ]]; then
  echo "Using graphdb.properties overrides"
  az keyvault secret show --vault-name ${key_vault_name} --name graphdb-properties | jq -rj .value | base64 -d >> /etc/graphdb/graphdb.properties
fi

# Appends environment overrides to GDB_JAVA_OPTS
if [[ $secrets == *"graphdb-java-options"* ]]; then
  echo "Using GDB_JAVA_OPTS overrides"
  extra_graphdb_java_options=$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-java-options | jq -rj .value | base64 -d)
  (
    source /etc/graphdb/graphdb.env
    echo "GDB_JAVA_OPTS=$GDB_JAVA_OPTS $extra_graphdb_java_options" >> /etc/graphdb/graphdb.env
  )
fi

# Configure the GraphDB backup cron job

cat <<-EOF > /usr/bin/graphdb_backup
#!/bin/bash

set -euxo pipefail

az login --identity

RESOURCE_GROUP="\$(az vmss list --query "[0].resourceGroup" --output tsv)"

# TODO change secret name when exists
GRAPHDB_ADMIN_PASSWORD="\$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-password --query "value" --output tsv)"
NODE_STATE="\$(curl --silent --fail --user "admin:\$GRAPHDB_ADMIN_PASSWORD" localhost:7200/rest/cluster/node/status | jq -r .nodeState)"

if [ "\$NODE_STATE" != "LEADER" ]; then
  echo "current node is not a leader, but \$NODE_STATE"
  exit 0
fi

BACKUP_NAME="\$(date +'%Y-%m-%d_%H-%M-%S').tar"
TEMP_BACKUP_DIR="/var/opt/graphdb/"
BLOB_URL="${backup_storage_container_url}/\$${BACKUP_NAME}"

function trigger_backup {
  curl -X POST --output "\$${TEMP_BACKUP_DIR}\$${BACKUP_NAME}" -H 'Content-Type: application/json' 'http://localhost:7200/rest/recovery/backup'
  upload_to_azure_storage
}

function upload_to_azure_storage {
  az storage blob upload --file "\$${TEMP_BACKUP_DIR}\$${BACKUP_NAME}" --blob-url "\$BLOB_URL" --auth-mode login --validate-content
}

trigger_backup

# Delete local backup file after upload
rm "\$${TEMP_BACKUP_DIR}\$${BACKUP_NAME}"

echo "Backup and upload completed successfully."

EOF

chmod +x /usr/bin/graphdb_backup
echo "${backup_schedule} graphdb /usr/bin/graphdb_backup" > /etc/cron.d/graphdb_backup

# Set keepalive and file max size
echo 'net.ipv4.tcp_keepalive_time = 120' | tee -a /etc/sysctl.conf
echo 'fs.file-max = 262144' | tee -a /etc/sysctl.conf

sysctl -p

# TODO: Monitoring/instrumenting

systemctl daemon-reload
systemctl start graphdb
systemctl enable graphdb-cluster-proxy.service
systemctl start graphdb-cluster-proxy.service

echo "Finished GraphDB instance configuration"
