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

disk_attach_create() {
  COUNTER=$1
  # Checks if a disk is attached (handles Terraform apply updates to the userdata script on a running instance)
  if [ -z "$ATTACHED_DISK" ]; then

    for i in $(seq 1 6); do
      # Wait for existing disks in the Resource group, which are unattached
      existingUnattachedDisk=$(
        az disk list --resource-group $RESOURCE_GROUP \
          --query "[?diskState=='Unattached' && starts_with(name, 'disk-$${RESOURCE_PREFIX}') && zones[0]=='$${ZONE_ID}'].{Name:name}" \
          --output tsv
      )

      if [ -z "$${existingUnattachedDisk:-}" ]; then
        echo 'Disk not yet available'
        sleep $RETRY_DELAY
      else
        break
      fi
    done

    # If there isn't an available disk after 30 seconds, will attempt to create a new one.
    if [ -z "$existingUnattachedDisk" ]; then
      echo "Creating a new managed disk"
      # Gets number of managed disks in the current AZ
      DISKS_IN_ZONE=$(az disk list --resource-group $RESOURCE_GROUP --query "length([?zones[0]=='$${ZONE_ID}'])" --output tsv)

      # Increment the number for the new name
      DISK_ORDER=$((DISKS_IN_ZONE + 1))

      while [ $COUNTER -le $MAX_RETRIES ]; do
        # Construct the disk name
        DISK_NAME="disk-$${RESOURCE_PREFIX}-$${ZONE_ID}-$${DISK_ORDER}"

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
          # It's unlikely but possible for the creation to fail if another instance in the same AZ is creating a disk with the same ID
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
    availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'disk-$${RESOURCE_PREFIX}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)

    # It's possible the created disk to be stolen by another VM starting at the same time in the same AZ
    # That's why we retry if this occurs.
    if [ -z "$availableDisks" ]; then
      echo "Something went wrong, no available disks, Retrying..."
      disk_attach_create 0
      availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'disk-$${RESOURCE_PREFIX}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)
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

  # Gets device name based on LUN 2
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
