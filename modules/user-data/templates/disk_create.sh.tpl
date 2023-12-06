#!/bin/bash

set -euxo pipefail

echo "######################################"
echo "#          Disk Provisioning         #"
echo "######################################"

# Find/create/attach volumes
INSTANCE_HOSTNAME=\'$(hostname)\'
RESOURCE_GROUP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
VMSS_NAME=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-01-01&format=text")
INSTANCE_ID=$(basename $(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
ZONE_ID=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/zone?api-version=2021-01-01&format=text")
REGION_ID=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-01-01&format=text")

# Do NOT change the LUN. Based on this we find and mount the disk in the VM
LUN=2
DISK_IOPS=${disk_iops_read_write}
DISK_THROUGHPUT=${disk_mbps_read_write}
DISK_SIZE_GB=${disk_size_gb}
ATTACHED_DISK=$(az vmss list-instances --resource-group "$RESOURCE_GROUP" --name "$VMSS_NAME" --query "[?instanceId=='$INSTANCE_ID'].storageProfile.dataDisks[].name" --output tsv)

disk_attach_create() {
  # Checks if a disk is attached (handles terraform apply updates to the userdata script)
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
        sleep 10
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

      MAX_RETRIES=3

      while [ $DISK_ORDER -le $MAX_RETRIES ]; do
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
          break # Exit the loop if disk creation is successful
        else
          echo "Disk creation failed. Retrying with incremented disk order..."
          # Increment the disk order for the next retry
          DISK_ORDER=$((DISK_ORDER + 1))
        fi
      done

      # Check if the maximum number of retries has been reached
      if [ $DISK_ORDER -gt $MAX_RETRIES ]; then
        echo "Disk creation failed after $MAX_RETRIES retries. Exiting."
      fi
    fi

    # Try to attach an existing managed disk
    availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'Disk-$${RESOURCE_GROUP}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)

    if [ -z "$availableDisks" ]; then
      echo "Something went wrong, no available disks, Retrying..."
      # It's possible the created disk to be stolen by another VM starting at the same time in the same AZ
      # That's why we retry if this occurs.
      disk_attach_create
      availableDisks=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && starts_with(name, 'Disk-$${RESOURCE_GROUP}') && zones[0]=='$${ZONE_ID}'].{Name:name}" --output tsv)
    fi

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
}

disk_attach_create

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
