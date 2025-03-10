#!/bin/bash

# This script focuses on the GraphDB node joining the cluster if the scale set spawns a new VM instance with a new volume.
#
# It performs the following tasks:
#  * Retrieves metadata about the Azure instance, including the resource group, instance ID, DNS zone name, and GraphDB admin password.
#  * Checks the availability of GraphDB nodes and identifies the leader node in the cluster.
#  * Monitors the presence of the Raft directory, if no Raft directory is found in 150 seconds:
#    * Waits for the total quorum of the cluster to be achieved.
#    * Initiates the addition of the current node to the cluster by contacting the leader node.
#  * Provides feedback on the successful completion of the script execution.

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

RESOURCE_GROUP=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-01-01&format=text")
INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
DNS_ZONE_NAME=$(az network private-dns zone list --query "[].name" --output tsv)
GRAPHDB_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
CURRENT_NODE_NAME=$(cat /var/opt/graphdb/node_dns_name)
RAFT_DIR="/var/opt/graphdb/node/data/raft"
LEADER_NODE=""

readarray -t NODES <<<"$(az network private-dns record-set list \
  --zone $DNS_ZONE_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'node')].name" \
  --output tsv)"

# This function should be used only after the Leader node is found
get_cluster_state() {
  curl_response=$(curl "http://$${LEADER_NODE}/rest/monitor/cluster" -s -u "admin:$GRAPHDB_PASSWORD")
  nodes_in_cluster=$(echo "$curl_response" | grep -oP 'graphdb_nodes_in_cluster \K\d+')
  nodes_in_sync=$(echo "$curl_response" | grep -oP 'graphdb_nodes_in_sync \K\d+')
  echo "$nodes_in_cluster $nodes_in_sync"
}

# Function to wait until total quorum is achieved
wait_for_total_quorum() {
  while true; do
    cluster_metrics=$(get_cluster_state)
    nodes_in_cluster=$(echo "$cluster_metrics" | awk '{print $1}')
    nodes_in_sync=$(echo "$cluster_metrics" | awk '{print $2}')

    if [ "$nodes_in_sync" -eq "$nodes_in_cluster" ]; then
      log_with_timestamp "Total quorum achieved: graphdb_nodes_in_sync: $nodes_in_sync equals graphdb_nodes_in_cluster: $nodes_in_cluster"
      break
    else
      log_with_timestamp "Waiting for total quorum... (graphdb_nodes_in_sync: $nodes_in_sync, graphdb_nodes_in_cluster: $nodes_in_cluster)"
      sleep 30
    fi
  done
}

join_cluster() {

  echo "#########################"
  echo "#    Joining cluster    #"
  echo "#########################"

  # Waits for all nodes to be available (Handles rolling upgrades)
  for node in "$${NODES[@]}"; do
    while ! check_gdb "$node.$${DNS_ZONE_NAME}"; do
      log_with_timestamp "Waiting for GDB $node.$${DNS_ZONE_NAME} to start"
      sleep 5
    done
  done

  # Iterates all nodes and looks for a Leader node to extract its address.
  while [ -z "$LEADER_NODE" ]; do
    for node in "$${NODES[@]}"; do
      endpoint="http://$node.$${DNS_ZONE_NAME}:7200/rest/cluster/group/status"
      log_with_timestamp "Checking leader status for $node.$${DNS_ZONE_NAME}"

      # Gets the address of the node if nodeState is LEADER, grpc port is returned therefor we replace port 7300 to 7200
      LEADER_ADDRESS=$(curl -s "$endpoint" -u "admin:$${GRAPHDB_PASSWORD}" | jq -r '.[] | select(.nodeState == "LEADER") | .address' | sed 's/7300/7200/')
      if [ -n "$${LEADER_ADDRESS}" ]; then
        LEADER_NODE=$LEADER_ADDRESS
        log_with_timestamp "Found leader address $LEADER_ADDRESS"
        break 2 # Exit both loops
      else
        log_with_timestamp "No leader found at $node"
      fi
    done

    log_with_timestamp "No leader found on any node. Retrying..."
    sleep 5
  done

  log_with_timestamp "Trying to delete $CURRENT_NODE_NAME"
  # Removes node if already present in the cluster config
  curl -X DELETE -s \
    --fail-with-body \
    -o "/dev/null" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -w "%%{http_code}" \
    -u "admin:$${GRAPHDB_PASSWORD}" \
    -d "{\"nodes\": [\"$${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}:7300\"]}" \
    "http://$${LEADER_NODE}/rest/cluster/config/node" || true

  # Waits for total quorum of the cluster before continuing with joining the cluster
  wait_for_total_quorum

  log_with_timestamp "Attempting to add $${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}:7300 to the cluster"
  # This operation might take a while depending on the size of the repositories.

  retry_count=0
  max_retries=3
  retry_interval=300 # 5 minutes in seconds

  while [ $retry_count -lt $max_retries ]; do
    CURL_MAX_REQUEST_TIME=21600 # 6 hours

    ADD_NODE=$(
      curl -X POST -s \
        -m $CURL_MAX_REQUEST_TIME \
        -o "/dev/null" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -w "%%{http_code}" \
        -u "admin:$${GRAPHDB_PASSWORD}" \
        -d"{\"nodes\": [\"$${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}:7300\"]}" \
        "http://$${LEADER_NODE}/rest/cluster/config/node"
    )
    if [[ "$ADD_NODE" == 200 ]]; then
      log_with_timestamp "$${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME} was successfully added to the cluster."
      break
    else
      log_with_timestamp "Node $${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME} failed to join the cluster, check the logs!"
      if [ $retry_count -lt $((max_retries - 1)) ]; then
        log_with_timestamp "Retrying in 5 minutes..."
        sleep $retry_interval
      fi
      retry_count=$((retry_count + 1))
    fi
  done

  if [[ "$ADD_NODE" != 200 ]]; then
    log_with_timestamp "Node $${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}  failed to join the cluster after $max_retries attempts, check the logs!"
  fi
}

# The initial provisioning of the VMSS in Azure may take a while
# therefore we need to be sure that this is not triggered before the first cluster initialization.
# Wait for 150 seconds, break if the raft folder appears (Handles cluster initialization).

for i in {1..30}; do
  if [ ! -d "$RAFT_DIR" ]; then
    log_with_timestamp "Raft directory not found yet. Waiting (attempt $i of 30)..."
    sleep 5
    if [ $i == 30 ]; then
      log_with_timestamp "$RAFT_DIR folder is not found, joining the current node to the cluster"
      join_cluster
      break
    fi
  else
    log_with_timestamp "Found Raft directory"
    if [ -z "$(ls -A $RAFT_DIR)" ]; then
      log_with_timestamp "Found $RAFT_DIR folder, but it is empty, please check the data folder and proceed by manually adding the node to the cluster"
      break
    else
      break
    fi
  fi
done

echo "###########################"
echo "#    Script completed     #"
echo "###########################"
