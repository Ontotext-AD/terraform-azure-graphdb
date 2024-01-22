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
RESOURCE_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text")
# Do NOT change the LUN. Based on this we find and mount the disk in the VM
LUN=2
DISK_STORAGE_TYPE=${disk_storage_account_type}
DISK_NETWORK_ACCESS_POLICY=${disk_network_access_policy}
DISK_PUBLIC_ACCESS_POLICY=${disk_public_network_access}
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
          --sku $DISK_STORAGE_TYPE \
          --zone $ZONE_ID \
          --disk-iops-read-write $DISK_IOPS \
          --disk-mbps-read-write $DISK_THROUGHPUT \
          --tags createdBy=$INSTANCE_HOSTNAME \
          --public-network-access $DISK_PUBLIC_ACCESS_POLICY \
          --network-access-policy $DISK_NETWORK_ACCESS_POLICY

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
  echo "Device $graphdb_device is not available. Something went wrong. \n Retrying disk creation ..."
  # If for any reason the disk is not available this will reattempt to create and attach it.
  disk_attach_create 0
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
  local DNS_RECORD="$1"
  # Checks if a record with the current instance IP is present
  IP_RECORD_PRESENT=$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?aRecords[?ipv4Address=='$IP_ADDRESS'].ipv4Address].name" --output tsv)
  # If no record is present for the current IP check which node is missing and assign the IP to it.
  if [ -z "$IP_RECORD_PRESENT" ]; then
    echo "Pinging $DNS_RECORD"
      if ping -c 5 "$DNS_RECORD"; then
        echo "Ping successful"
      else
        echo "Ping failed for $DNS_RECORD"
        # Extracts the record name
        RECORD_NAME=$(echo "$DNS_RECORD" | awk -F'.' '{print $1}')
        az network private-dns record-set a update --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME --set ARecords[0].ipv4Address="$IP_ADDRESS"
      fi
  else
    echo "Record for this IP is present in the Private DNS"
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
    # Have to first create and then add, see https://github.com/Azure/azure-cli/issues/27374
    az network private-dns record-set a create --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $RECORD_NAME
    az network private-dns record-set a add-record --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --record-set-name $RECORD_NAME --ipv4-address "$IP_ADDRESS"
  else
    for record in "$${ALL_FQDN_RECORDS[@]}"; do
      echo "Checking DNS record $record"
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
secrets=$(az appconfig kv list --name ${app_config_name} --auth-mode login | jq .[].key)

# Get the license
az appconfig kv show --name ${app_config_name} --auth-mode login --key graphdb-license | jq -r .value | base64 -d > /etc/graphdb/graphdb.license

# Get the cluster token
graphdb_cluster_token=$(az appconfig kv show --name ${app_config_name} --auth-mode login --key graphdb-cluster-token | jq -r .value | base64 -d)

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
  az appconfig kv show --name ${app_config_name} --auth-mode login --key graphdb-properties | jq -r .value | base64 -d >> /etc/graphdb/graphdb.properties
fi

# Appends environment overrides to GDB_JAVA_OPTS
if [[ $secrets == *"graphdb-java-options"* ]]; then
  echo "Using GDB_JAVA_OPTS overrides"
  extra_graphdb_java_options=$(az appconfig kv show --name ${app_config_name} --auth-mode login --key graphdb-java-options | jq -r .value | base64 -d)
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
GRAPHDB_ADMIN_PASSWORD="\$(az appconfig kv show --name ${app_config_name} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
NODE_STATE="\$(curl --silent --fail --user "admin:\$GRAPHDB_ADMIN_PASSWORD" localhost:7200/rest/cluster/node/status | jq -r .nodeState)"

if [ "\$NODE_STATE" != "LEADER" ]; then
  echo "current node is not a leader, but \$NODE_STATE"
  exit 0
fi

BACKUP_NAME="\$(date +'%Y-%m-%d_%H-%M-%S').tar"
max_retries=3
retry_count=0

while [ "\$retry_count" -lt "\$max_retries" ]; do
  start_time=\$(date +%s)

  response_code=\$(curl -X POST --write-out %%{http_code} --silent --output /dev/null \
    --header 'Content-Type: application/json' \
    -u "admin:\$GRAPHDB_ADMIN_PASSWORD" \
    --header 'Accept: application/json' \
    -d "{\"bucketUri\": \"az://${backup_storage_container_name}/\$${BACKUP_NAME}?blob_storage_account=${backup_storage_account_name}\", \"backupOptions\": {\"backupSystemData\": true}}" \
    'http://localhost:7200/rest/recovery/cloud-backup'
  )

  end_time=\$(date +%s)
  elapsed_time=\$((end_time - start_time))

  if [ "\$response_code" -eq 200 ]; then
    echo "Backup and upload completed successfully in \$elapsed_time seconds."
    break
  else
    echo "Failed to complete the backup and upload. HTTP Response Code: \$response_code"
    echo "Request took: \$elapsed_time"

    if [ "\$retry_count" -eq "\$max_retries" ]; then
      echo "Max retries reached. Backup could not be created. Exiting..."
    else
      echo "Retrying..."
    fi

    ((retry_count=retry_count + 1))
    sleep 5
  fi

done

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

echo "#########################"
echo "#    Setup Telegraf     #"
echo "#########################"

echo "Getting GDB password"
GRAPHDB_ADMIN_PASSWORD="$(az appconfig kv show --name ${app_config_name} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"

# Installs Telegraf
curl -s https://repos.influxdata.com/influxdata-archive.key > influxdata-archive.key
echo '943666881a1b8d9b849b74caebf02d3465d6beb716510d86a39f6c8e8dac7515 influxdata-archive.key' | sha256sum -c && cat influxdata-archive.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive.gpg > /dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
apt-get update && apt-get install telegraf

# Overrides the config file
cat <<-EOF > /etc/telegraf/telegraf.conf
  [[inputs.prometheus]]
    urls = ["http://localhost:7200/rest/monitor/infrastructure", "http://localhost:7200/rest/monitor/structures"]
    username = "admin"
    password = "$${GRAPHDB_ADMIN_PASSWORD}"

  [[outputs.azure_monitor]]
    namespace_prefix = "Telegraf/"
    region = "$REGION_ID"
    resource_id = "$RESOURCE_ID"
EOF

systemctl restart telegraf

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

check_gdb() {
  if [ -z "$1" ]; then
    echo "Error: IP address or hostname is not provided."
    return 1
  fi

  local gdb_address="$1:7200/rest/monitor/infrastructure"
  if curl -s --head -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" --fail "$gdb_address" >/dev/null; then
    echo  "Success, GraphDB node $gdb_address is available"
    return 0
  else
    echo "GraphDB node $gdb_address is not available yet"
    return 1
  fi
}

# Waits for 3 DNS records to be available
wait_dns_records() {
  ALL_FQDN_RECORDS_COUNT=($(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, 'node')].fqdn | length(@)"))
  if [ "$${ALL_FQDN_RECORDS_COUNT}" -ne 3 ]; then
    sleep 5
    wait_dns_records
  else
    echo "Private DNS zone record count is $${ALL_FQDN_RECORDS_COUNT}"
  fi
}

wait_dns_records

readarray -t ALL_DNS_RECORDS <<< "$(az network private-dns record-set list -z $DNS_ZONE_NAME --resource-group $RESOURCE_GROUP --query "[?contains(name, 'node')].fqdn" --output tsv)"
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

echo "All GDB instances are available. Creating cluster"

#  Only the instance with lowest ID would attempt to create the cluster
if [ "$INSTANCE_ID" == "$${LOWEST_INSTANCE_ID}" ]; then

  for ((i = 1; i <= $MAX_RETRIES; i++)); do
    IS_CLUSTER=$(curl -s -o /dev/null -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" -w "%%{http_code}" http://localhost:7200/rest/monitor/cluster)
    # 000 = no HTTP code was received
    if [[ "$IS_CLUSTER" == 000 ]]; then
      echo "Retrying ($i/$MAX_RETRIES) after $RETRY_DELAY seconds..."
      sleep $RETRY_DELAY
    elif [ "$IS_CLUSTER" == 503 ]; then
      CLUSTER_CREATED=$(curl -X POST -s http://localhost:7200/rest/cluster/config \
        -w "%%{http_code}" \
        -H 'Content-type: application/json' \
        -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" \
        -d "{\"nodes\": [\"node-1.$${DNS_ZONE_NAME}:7300\",\"node-2.$${DNS_ZONE_NAME}:7300\",\"node-3.$${DNS_ZONE_NAME}:7300\"]}"
      )
      [ "$CLUSTER_CREATED" == 200 ] && { echo "GraphDB cluster successfully created!"; break; }
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
  SET_PASSWORD=$(curl --location -s -w "%%{http_code}" --request PATCH 'http://localhost:7200/rest/security/users/admin' \
    --header 'Content-Type: application/json' \
    --data "{ \"password\": \"$${GRAPHDB_ADMIN_PASSWORD}\" }"
    )
  if [[ "$SET_PASSWORD" == 200 ]]; then
    echo "Set GraphDB password successfully"
  else
    echo "Failed setting GraphDB password. Please check the logs"
  fi

  # Enable the security
  ENABLED_SECURITY=$(curl -X POST -s -w "%%{http_code}" --header 'Content-Type: application/json' --header 'Accept: */*' -d 'true' 'http://localhost:7200/rest/security')
  if [[ "$ENABLED_SECURITY" == 200 ]]; then
    echo "Enabled GraphDB security successfully"
  else
    echo "Failed enabling GraphDB security. Please check the logs"
  fi
fi

echo "###########################"
echo "#    Script completed     #"
echo "###########################"
