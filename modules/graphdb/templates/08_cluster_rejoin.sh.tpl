#!/bin/bash

# This script focuses on the GraphDB node rejoining the cluster if the scale set spawns a new VM instance with a new volume.
#
# It performs the following tasks:
#   * Rejoins the node to the cluster if raft folder is not found or empty

set -euo pipefail

INSTANCE_ID=$(basename $(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceId?api-version=2021-01-01&format=text"))
DNS_ZONE_NAME=$(az network private-dns zone list --query "[].name" --output tsv)
GRAPHDB_ADMIN_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
CURRENT_NODE_NAME=$(cat /tmp/node_name)
RAFT_DIR="/var/opt/graphdb/node/data/raft"
NODES=("node-1" "node-2" "node-3")
LEADER_NODE=""

check_gdb() {
  local gdb_address="$1:7200/rest/monitor/infrastructure"
  if curl -s --head -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" --fail "$gdb_address" >/dev/null; then
    echo "Success, GraphDB node $gdb_address is available"
    return 0
  else
    echo "GraphDB node $gdb_address is not available yet"
    return 1
  fi
}

rejoin_cluster() {

  echo "#############################"
  echo "#    Rejoin cluster node    #"
  echo "#############################"

  # Waits for all nodes to be available (Handles rolling upgrades)
  for node in "$${NODES[@]}"; do
    while ! check_gdb "$node.$${DNS_ZONE_NAME}"; do
      echo "Waiting for GDB $node.$${DNS_ZONE_NAME} to start"
      sleep 5
    done
  done

  # Iterates all nodes and looks for a Leader node to extract its address.
  while [ -z "$LEADER_NODE" ]; do
    for node in "$${NODES[@]}"; do
      endpoint="http://$node.$${DNS_ZONE_NAME}:7200/rest/cluster/group/status"
      echo "Checking leader status for $node.$${DNS_ZONE_NAME}"

      # Gets the address of the node if nodeState is LEADER, grpc port is returned therefor we replace port 7300 to 7200
      LEADER_ADDRESS=$(curl -s "$endpoint" -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" | jq -r '.[] | select(.nodeState == "LEADER") | .address' | sed 's/7300/7200/')
      if [ -n "$${LEADER_ADDRESS}" ]; then
        LEADER_NODE=$LEADER_ADDRESS
        echo "Found leader address $LEADER_ADDRESS"
        break 2 # Exit both loops
      else
        echo "No leader found at $node"
      fi
    done

    echo "No leader found on any node. Retrying..."
    sleep 5
  done

  echo "Attempting to rejoin the cluster"
  # Step 1: Remove the node from the cluster.
  echo "Attempting to delete $${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}:7300 from the cluster"

  curl -X DELETE -s \
    --fail-with-body \
    -o "/dev/null" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -w "%%{http_code}" \
    -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" \
    -d "{\"nodes\": [\"$${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}:7300\"]}" \
    "http://$${LEADER_NODE}/rest/cluster/config/node"

  # Step 2: Add the current node to the cluster with the same address.
  echo "Attempting to add $${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}:7300 to the cluster"
  # This operation might take a while depending on the size of the repositories.
  CURL_MAX_REQUEST_TIME=21600 # 6 hours

  ADD_NODE=$(
    curl -X POST -s \
      -m $CURL_MAX_REQUEST_TIME \
      -o "/dev/null" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json' \
      -w "%%{http_code}" \
      -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" \
      -d"{\"nodes\": [\"$${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME}:7300\"]}" \
      "http://$${LEADER_NODE}/rest/cluster/config/node"
  )

  if [[ "$ADD_NODE" == 200 ]]; then
    echo "$node.$${DNS_ZONE_NAME} was successfully added to the cluster."
  else
    echo "Node $${CURRENT_NODE_NAME}.$${DNS_ZONE_NAME} failed to rejoin the cluster, check the logs!"
  fi
}

# Check if the Raft directory exists
if [ ! -d "$RAFT_DIR" ]; then
  echo "$RAFT_DIR folder is missing, waiting..."

  # The initial provisioning of the VMSS in Azure may take a while
  # therefore we need to be sure that this is not triggered before the first cluster initialization.
  # Wait for 150 seconds, break if the folder appears (Handles cluster initialization).

  for i in {1..30}; do
    if [ ! -d "$RAFT_DIR" ]; then
      echo "Raft directory not found yet. Waiting (attempt $i of 30)..."
      sleep 5
      if [ $i == 30 ]; then
        echo "$RAFT_DIR folder is not found, rejoining node to cluster"
        rejoin_cluster
      fi
    else
      echo "Found Raft directory"
      if [ -z "$(ls -A $RAFT_DIR)" ]; then
        echo "$RAFT_DIR folder is empty, rejoining node to cluster"
        rejoin_cluster
      else
        break
      fi
    fi
  done
fi

echo "###########################"
echo "#    Script completed     #"
echo "###########################"
