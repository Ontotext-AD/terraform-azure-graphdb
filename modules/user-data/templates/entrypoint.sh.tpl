#!/usr/bin/env bash

set -euo pipefail

echo "#################################################"
echo "#      Begin configuring GraphDB instance       #"
echo "#################################################"

# Stop in order to override configurations
echo "Stopping GraphDB"
systemctl stop graphdb

# Login in Azure CLI with managed identity (user or system assigned)
az login --identity

# Find/create/attach volumes
INSTANCE_HOSTNAME=\'$(hostname)\'
RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
VMSS_NAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-01-01&format=text")
INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
ZONE_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/zone?api-version=2021-01-01&format=text")
REGION_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-01-01&format=text")
# Do NOT change the LUN. Based on this we find and mount the disk in the VM
LUN=2
DISK_IOPS=${disk_iops_read_write}
DISK_THROUGHPUT=${disk_mbps_read_write}
DISK_SIZE_GB=${disk_size_gb}
ATTACHED_DISK=$(
  az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[?instanceId=='$INSTANCE_ID'].storageProfile.dataDisks[].name" --output tsv
  )
# Global retry settings
MAX_RETRIES=3
RETRY_DELAY=5

echo "###########################################"
echo "#    Creating/Attaching managed disks     #"
echo "###########################################"

disk_attach_create() {
  COUNTER=$1
  # Checks if a disk is attached (handles Terraform apply updates to the userdata script on a running instance)
  if [ -z "$ATTACHED_DISK" ]; then

    for i in $(seq 1 6); do
      # Wait for existing disks in the VMSS which are unattached
      existingUnattachedDisk=$(
        az disk list --resource-group $RESOURCE_GROUP \
          --query "[?diskState=='Unattached' && starts_with(name, 'Disk-$${RESOURCE_GROUP}') && zones[0]=='$${ZONE_ID}'].{Name:name}" \
          --output tsv
      )

      if [ -z "$${existingUnattachedDisk:-}" ]; then
        echo 'Disk not yet available'
        sleep $RETRY_DELAY
      else
        break
      fi
    done

    if [ -z "$existingUnattachedDisk" ]; then
      echo "Creating a new managed disk"
      # Fetch the number of elements
      DISKS_IN_ZONE=$(az disk list --resource-group $RESOURCE_GROUP --query "length([?zones[0]=='$${ZONE_ID}'])" --output tsv)

      # Increment the number for the new name
      DISK_ORDER=$((DISKS_IN_ZONE + 1))

      while [ $COUNTER -le $MAX_RETRIES ]; do
        # Construct the disk name
        DISK_NAME="Disk-$${RESOURCE_GROUP}-$${ZONE_ID}-$${DISK_ORDER}"

        # Attempt to create the disk
        az disk create --resource-group $RESOURCE_GROUP \
          --name $DISK_NAME \
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

        # Check the exit status of the last command
        if [ $? -eq 0 ]; then
          echo "Disk creation successful."
          break
        else
          echo "Disk creation failed. Retrying with incremented disk order..."
          # Increment the disk order for the next retry
          DISK_ORDER=$((DISK_ORDER + 1))
          if [ $COUNTER -gt $MAX_RETRIES ]; then
            echo "Disk creation failed after $MAX_RETRIES retries. Exiting."
            break
          fi
          COUNTER=$((COUNTER + 1))
        fi
      done
    fi

    # Try to attach an existing managed disk
    availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'Disk-$${RESOURCE_GROUP}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)

    # It's possible the created disk to be stolen by another VM starting at the same time in the same AZ
    # That's why we retry if this occurs.
    if [ -z "$availableDisks" ]; then
      echo "Something went wrong, no available disks, Retrying..."
      disk_attach_create 0
      availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'Disk-$${RESOURCE_GROUP}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)
    fi

    echo "Attaching available disk $availableDisks."
    # Set Internal Field Separator to newline to handle spaces in names
    IFS=$'\n'
    # Would iterate through all available disks and attempt to attach them
    for availableDisk in $availableDisks; do
      az vmss disk attach --vmss-name $VMSS_NAME --resource-group $RESOURCE_GROUP --instance-id $INSTANCE_ID --lun $LUN --disk "$availableDisk" || true
    done
  else
    echo "Managed disk is attached"
  fi

  # Gets device name based on LUN
  graphdb_device=$(lsscsi --scsi --size | awk '/\[1:.*:0:2\]/ {print $7}')
}

disk_attach_create 0

echo "##########################################"
echo "#    Managed disk setup and mounting     #"
echo "##########################################"

# Check if the device is present after attaching the disk
if [ -b "$graphdb_device" ]; then
  echo "Device $graphdb_device is available."
else
  echo "Device $graphdb_device is not available. Something went wrong."
  exit 1
fi

# Create a file system if there isn't any
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
    echo "$graphdb_device $disk_mount_point ext4 defaults 0 2" >>/etc/fstab
  fi

  # Mount the disk
  mount "$disk_mount_point"
  echo "The disk at $graphdb_device is now mounted at $disk_mount_point."
  mkdir -p /var/opt/graphdb/node /var/opt/graphdb/cluster-proxy
  # TODO research how to avoid using chown, as it would be a slow operation if data is present.
  chown -R graphdb:graphdb /var/opt/graphdb
else
  echo "The disk at $graphdb_device is already mounted."
fi

echo "########################"
echo "#   DNS Provisioning   #"
echo "########################"
# This provides stable network addresses for GDB instances in Azure VMSS

IP_ADDRESS=$(hostname -I | awk '{print $1}')

for i in $(seq 1 6); do
  # Waits for DNS zone to be created and role assigned
  DNS_ZONE_NAME=$(az network private-dns zone list --query "[].name" --output tsv)
  if [ -z "$${DNS_ZONE_NAME:-}" ]; then
    echo 'Zone not available yet'
    sleep 10
  else
    break
  fi
done

# Get all FQDN records from the private DNS zone containing "node"
readarray -t ALL_FQDN_RECORDS <<< "$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, 'node')].fqdn" --output tsv)"
# Get all instance IDs for the current VMSS
INSTANCE_IDS=($(az vmss list-instances --resource-group $RESOURCE_GROUP --name $VMSS_NAME --query "[].instanceId" --output tsv))
# Sort instance IDs
SORTED_INSTANCE_IDs=($(echo "$${INSTANCE_IDS[@]}" | tr ' ' '\n' | sort))
# Find the lowest, middle and highest instance IDs
LOWEST_INSTANCE_ID=$${SORTED_INSTANCE_IDs[0]}
MIDDLE_INSTANCE_ID=$${SORTED_INSTANCE_IDs[1]}
HIGHEST_INSTANCE_ID=$${SORTED_INSTANCE_IDs[2]}

# Pings a DNS record, if no response is returned, will update the DNS record with the IP of the current instance
ping_and_set_dns_record() {
  local dns_record="$1"
  echo "Pinging $dns_record"
  if ping -c 5 "$dns_record"; then
    echo "Ping successful"
  else
    echo "Ping failed for $dns_record"
    # Extracts the record name
    RECORD_NAME=$(echo "$dns_record" | awk -F'.' '{print $1}')
    az network private-dns record-set a update --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --set ARecords[0].ipv4Address="$IP_ADDRESS"
  fi
}

# Assign DNS record name based on instanceId
for i in "$${!SORTED_INSTANCE_IDs[@]}"; do
  if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then
    RECORD_NAME="node-1"
  elif [ "$INSTANCE_ID" == "$${MIDDLE_INSTANCE_ID}" ]; then
    RECORD_NAME="node-2"
  elif [ "$INSTANCE_ID" == "$${HIGHEST_INSTANCE_ID}" ]; then
    RECORD_NAME="node-3"
  fi

  # Get the FQDN for the current instance
  FQDN=$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, '$RECORD_NAME')].fqdn" --output tsv)

  if [ -z "$${FQDN:-}" ]; then
    az network private-dns record-set a add-record --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --record-set-name $RECORD_NAME --ipv4-address "$IP_ADDRESS"
  else
    for record in "$${ALL_FQDN_RECORDS[@]}"; do
      ping_and_set_dns_record "$record"
    done
  fi

  break
done

# Gets the full DNS record for the current instance
node_dns=$(az network private-dns record-set a show --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --output tsv --query "fqdn" | rev | cut -c 2- | rev)

echo "#######################################"
echo "#   GraphDB configuration overrides   #"
echo "#######################################"

echo "Getting secrets"
secrets=$(az keyvault secret list --vault-name ${key_vault_name} --output json | jq .[].name)

# Get the license
az keyvault secret download --vault-name ${key_vault_name} --name graphdb-license --file /etc/graphdb/graphdb.license --encoding base64

# Get the cluster token
graphdb_cluster_token=$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-cluster-token | jq -rj .value | base64 -d)

echo "Writing override files"
# TODO: where is the vhost here?
cat <<EOF > /etc/graphdb/graphdb.properties
graphdb.auth.token.secret=$graphdb_cluster_token
graphdb.connector.port=7200
graphdb.external-url=http://$${node_dns}:7200/
graphdb.rpc.address=$${node_dns}:7300
EOF

cat <<EOF > /etc/graphdb-cluster-proxy/graphdb.properties
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
# Calculate 85% of total VM memory
jvm_max_memory=$(echo "$total_memory_gb * 0.85" | bc | cut -d'.' -f1)

mkdir -p /etc/systemd/system/graphdb.service.d/

cat <<EOF > /etc/systemd/system/graphdb.service.d/overrides.conf
[Service]
Environment="GDB_HEAP_SIZE=$${jvm_max_memory}g"
EOF

# TODO: overrides for the proxy?
# Appends configuration overrides to graphdb.properties
if [[ $secrets == *"graphdb-properties"* ]]; then
  echo "Using graphdb.properties overrides"
  az keyvault secret show --vault-name ${key_vault_name} --name graphdb-properties | jq -rj .value | base64 -d >>/etc/graphdb/graphdb.properties
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

echo "Completed applying overrides"

echo "#################################################"
echo "#    Configuring the GraphDB backup cron job    #"
echo "#################################################"

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
echo "Backup file created"

echo "#############################################"
echo "#    Setting keepalive and file max size    #"
echo "#############################################"

echo 'net.ipv4.tcp_keepalive_time = 120' | tee -a /etc/sysctl.conf
echo 'fs.file-max = 262144' | tee -a /etc/sysctl.conf

sysctl -p

# TODO: Monitoring/instrumenting

echo "###########################"
echo "#    Starting GraphDB     #"
echo "###########################"

systemctl daemon-reload
systemctl start graphdb
systemctl enable graphdb-cluster-proxy.service
systemctl start graphdb-cluster-proxy.service

echo "##################################"
echo "#    Beginning cluster setup     #"
echo "##################################"

GRAPHDB_ADMIN_PASSWORD="$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-password --query "value" --output tsv)"

check_gdb() {
  local gdb_address="$1:7200/rest/monitor/infrastructure"
  if curl -s --head -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" --fail $gdb_address >/dev/null; then
    echo  "Success, GraphDB node is available"
    return 0
  else
    echo "GraphDB node is not available yet"
    return 1
  fi
}

# Waits for 3 DNS records to be available
wait_dns_records() {
  ALL_FQDN_RECORDS_COUNT=($(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, 'node')].fqdn | length(@)"))
  if [ "$${ALL_FQDN_RECORDS_COUNT}" -ne 3 ]; then
    sleep 5
    wait_dns_records
  fi
}

wait_dns_records

# Check all instances are running
for record in "$${ALL_FQDN_RECORDS[@]}"; do
  echo $record
  # Removes the '.' at the end of the DNS address
  cleanedAddress=$${record%?}
  while ! check_gdb $cleanedAddress; do
    echo "Waiting for GDB $record to start"
    sleep $RETRY_DELAY
  done
done

echo "All GDB instances are available. Creating cluster"

if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then


  for ((i = 1; i <= $MAX_RETRIES; i++)); do
    IS_CLUSTER=$(curl -s -o /dev/null -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" -w "%%{http_code}" http://localhost:7200/rest/monitor/cluster)
    # 000 = no HTTP code was received
    if [[ "$IS_CLUSTER" == 000 ]]; then
      echo "Retrying ($i/$MAX_RETRIES) after $RETRY_DELAY seconds..."
      sleep $RETRY_DELAY
    elif [ "$IS_CLUSTER" == 503 ]; then
      curl -X POST http://localhost:7200/rest/cluster/config \
        -H 'Content-type: application/json' \
        -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" \
        -d "{\"nodes\": [\"node-1.$${DNS_ZONE_NAME}:7300\",\"node-2.$${DNS_ZONE_NAME}:7300\",\"node-3.$${DNS_ZONE_NAME}:7300\"]}"
    elif [ "$IS_CLUSTER" == 200 ]; then
      echo "Cluster exists"
      break
    else
      echo "Something went wrong! Check the logs"
    fi
  done
fi

echo "###########################################################"
echo "#    Changing admin user password and enable security     #"
echo "###########################################################"

is_security_enabled=$(curl -s -X GET --header 'Accept: application/json' -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" 'http://localhost:7200/rest/security')

# Check if GDB security is enabled
if [[ $is_security_enabled == "true" ]]; then
  echo "Security is enabled"
else
  # Set the admin password
  curl --location --request PATCH 'http://localhost:7200/rest/security/users/admin' \
    --header 'Content-Type: application/json' \
    --data "{ \"password\": \"$${GRAPHDB_ADMIN_PASSWORD}\" }"
  # Enable the security
  curl -X POST --header 'Content-Type: application/json' --header 'Accept: */*' -d 'true' 'http://localhost:7200/rest/security'
fi

echo "###########################"
echo "#    Script completed     #"
echo "###########################"

