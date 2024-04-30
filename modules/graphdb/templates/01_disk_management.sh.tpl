#!/bin/bash

# This script is designed for use in an Azure VMSS environment to manage and attach disks dynamically.
#
# It performs the following tasks:
#   * Retrieves metadata about the Azure instance, including the resource group, VM scale set name, instance ID, region, and zone.
#   * Checks if any managed disks are already attached to the virtual machine scale set (VMSS) instance.
#   * Attempts to create a new managed disk if no disks are available, considering retries in case of failures during creation.
#   * Attaches an available disk to the VMSS instance.
#   * Sets up and mounts the attached disk, creating a file system if necessary.
#   * Ensures the disk is automatically mounted on system startup by updating the /etc/fstab file.
#   * Verifies and reports the successful setup and mounting of the disk.

set -euo pipefail

echo "###########################################"
echo "#    Creating/Attaching managed disks     #"
echo "###########################################"

RESOURCE_PREFIX=${resource_name_prefix}
RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
VMSS_NAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-01-01&format=text")
INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
REGION_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-01-01&format=text")

ATTACHED_DISK=$(
  az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[?instanceId=='$INSTANCE_ID'].storageProfile.dataDisks[].name" --output tsv
)

INSTANCE_HOSTNAME=\'$(hostname)\'
ZONE_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/zone?api-version=2021-01-01&format=text")
DISK_STORAGE_TYPE=${disk_storage_account_type}
DISK_NETWORK_ACCESS_POLICY=${disk_network_access_policy}
DISK_PUBLIC_ACCESS_POLICY=${disk_public_network_access}
DISK_IOPS=${disk_iops_read_write}
DISK_THROUGHPUT=${disk_mbps_read_write}
DISK_SIZE_GB=${disk_size_gb}
disk_mount_point="/var/opt/graphdb"
# Do NOT change the LUN. Based on this we find and mount the disk in the VM instance.
LUN=2

MAX_RETRIES=3
RETRY_DELAY=5
# Terraform accepts bool variable for disk_public_network_access but the AZ CLI allows Disabled, Enabled as values
[ "$DISK_PUBLIC_ACCESS_POLICY" = true ] && DISK_PUBLIC_ACCESS_POLICY="Enabled" || DISK_PUBLIC_ACCESS_POLICY="Disabled"

wait_for_available_disk() {
  for i in $(seq 1 6); do
    existingUnattachedDisk=$(
      az disk list --resource-group $RESOURCE_GROUP \
        --query "[?diskState=='Unattached' && starts_with(name, 'disk-$${RESOURCE_PREFIX}') && zones[0]=='$${ZONE_ID}'].{Name:name}" \
        --output tsv
    )

    if [ -z "$existingUnattachedDisk" ]; then
      echo 'Disk not yet available'
      sleep $RETRY_DELAY
    else
      break
    fi
  done
}

create_managed_disk() {
  local counter=$1
  local disks_in_zone=$(az disk list --resource-group $RESOURCE_GROUP --query "length([?zones[0]=='$${ZONE_ID}'])" --output tsv)
  local disk_order=$((disks_in_zone + 1))

  while [ $counter -le $MAX_RETRIES ]; do
    local disk_name="disk-$${RESOURCE_PREFIX}-$${ZONE_ID}-$${disk_order}"

    az disk create --resource-group $RESOURCE_GROUP \
      --name $disk_name \
      --size-gb $DISK_SIZE_GB \
      --location $REGION_ID \
      --sku $DISK_STORAGE_TYPE \
      --zone $ZONE_ID \
      --disk-iops-read-write $DISK_IOPS \
      --disk-mbps-read-write $DISK_THROUGHPUT \
      --tags createdBy=$INSTANCE_HOSTNAME \
      --public-network-access $DISK_PUBLIC_ACCESS_POLICY \
      --network-access-policy $DISK_NETWORK_ACCESS_POLICY

    if [ $? -eq 0 ]; then
      echo "Disk creation successful."
      break
    else
      echo "Disk creation failed. Retrying with incremented disk order..."
      disk_order=$((disk_order + 1))
      if [ $counter -gt $MAX_RETRIES ]; then
        echo "Disk creation failed after $MAX_RETRIES retries. Exiting."
        break
      fi
      counter=$((counter + 1))
    fi
  done
}

check_existing_disk_attachments() {
  for availableDisk in $availableDisks; do
    attachingVM=$(az disk list --query "[?name=='$availableDisk'].managedBy" --output tsv)
    if [ "$attachingVM" != "" ]; then
      echo "Disk $availableDisk is already being attached to VM $attachingVM. Skipping attachment."
      availableDisks=$(echo "$availableDisks" | grep -v "$availableDisk")
    fi
  done
}

attach_available_disks() {
  if [ -n "$availableDisks" ]; then
    echo "Attaching available disk $availableDisks."
    IFS=$'\n'
    for availableDisk in $availableDisks; do
      az vmss disk attach --vmss-name $VMSS_NAME --resource-group $RESOURCE_GROUP --instance-id $INSTANCE_ID --lun $LUN --disk "$availableDisk" || true
    done
  else
    echo "No available disks to attach."
  fi
}

disk_attach_create() {
  COUNTER=$1
  if [ -z "$ATTACHED_DISK" ]; then
    wait_for_available_disk

    if [ -z "$existingUnattachedDisk" ]; then
      echo "Creating a new managed disk"
      create_managed_disk $COUNTER
    fi

    availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'disk-$${RESOURCE_PREFIX}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)

    check_existing_disk_attachments

    attach_available_disks
  else
    echo "Managed disk is attached"
  fi

  # Gets device name based on LUN 2
  graphdb_device=$(lsscsi --scsi --size | grep -v 'cd/dvd' | awk '/\[*:.*:0:2\]/ {print $7}')
}

disk_attach_create 0

echo "##########################################"
echo "#    Managed disk setup and mounting     #"
echo "##########################################"

# Check if the device is present after attaching the disk
if [ -b "$graphdb_device" ]; then
  echo "Device $graphdb_device is available."
else
  echo "Device $graphdb_device is not available. Something went wrong. Retrying disk creation ..."
  # If for any reason the disk is not available this will reattempt to create and attach it.
  disk_attach_create 0
fi

# Create a file system if there isn't any
if [ "$graphdb_device: data" = "$(file -s $graphdb_device)" ]; then
  mkfs -t ext4 $graphdb_device
fi

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
