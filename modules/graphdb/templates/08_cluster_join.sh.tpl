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
M2M_ENABLED='${m2m_enabled}'
M2M_CLIENT_ID='${m2m_client_id}'
M2M_CLIENT_SECRET='${m2m_client_secret}'
M2M_TENANT_ID='${tenant_id}'
M2M_SCOPE='${scope}'
APP_CONFIGURATION_ENDPOINT='${app_configuration_endpoint}'
gdb_init_auth

if [[ "$M2M_ENABLED" != "true" ]]; then
  GRAPHDB_PASSWORD="$(az appconfig kv show --endpoint ${app_configuration_endpoint} --auth-mode login --key graphdb-password | jq -r .value | base64 -d)"
fi
CURRENT_NODE_NAME=$(cat /var/opt/graphdb/node_dns_name)
EXPECTED_NODE_COUNT="${node_count}"
RAFT_DIR="/var/opt/graphdb/node/data/raft"
LEADER_NODE=""

readarray -t NODES <<<"$(az network private-dns record-set list \
  --zone $DNS_ZONE_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'node')].name" \
  --output tsv)"

# This function should be used only after the Leader node is found
get_cluster_state() {
  curl_response=$(gdb_curl "http://$${LEADER_NODE}/rest/monitor/cluster" -s)
  nodes_in_cluster=$(echo "$curl_response" | grep -oP 'graphdb_nodes_in_cluster \K\d+')
  nodes_in_sync=$(echo "$curl_response" | grep -oP 'graphdb_nodes_in_sync \K\d+')
  disconnected_nodes=$(echo "$curl_response" | grep -oP 'graphdb_nodes_disconnected \K\d+')
  echo "$nodes_in_cluster $nodes_in_sync $disconnected_nodes"
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

      # Gets the address of the node if nodeState is LEADER, grpc port is returned therefore we replace port 7300 to 7200
      LEADER_ADDRESS=$(
        gdb_curl -s "$endpoint" \
        | jq -r '.[] | select(.nodeState == "LEADER") | .address' \
        | sed 's/7300/7200/'
      )

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

  #################################################################
  # Only continue if:
  #   - graphdb_nodes_disconnected > 0
  #     OR
  #   - EXPECTED_NODE_COUNT != nodes_in_cluster
  #################################################################
  cluster_metrics=$(get_cluster_state)
  # cluster_metrics is "nodes_in_cluster nodes_in_sync disconnected_nodes"
  nodes_in_cluster=$(echo "$cluster_metrics" | awk '{print $1}')
  disconnected_nodes=$(echo "$cluster_metrics" | awk '{print $3}')

  # Fallback / sanity check: if we can't parse, skip automatic join
  if ! [[ "$disconnected_nodes" =~ ^[0-9]+$ ]]; then
    log_with_timestamp "Could not parse graphdb_nodes_disconnected from cluster metrics: '$cluster_metrics'. Skipping automatic join."
    return 0
  fi

  if ! [[ "$nodes_in_cluster" =~ ^[0-9]+$ ]]; then
    log_with_timestamp "Could not parse graphdb_nodes_in_cluster from cluster metrics: '$cluster_metrics'. Skipping automatic join."
    return 0
  fi

  should_join=false

  # Case 1: there are disconnected nodes
  if [ "$disconnected_nodes" -gt 0 ]; then
    log_with_timestamp "graphdb_nodes_disconnected=$disconnected_nodes (> 0). Will try to join $${CURRENT_NODE_NAME}."
    should_join=true
  fi

  # Case 2: cluster size is not what we expect
  if [[ "$EXPECTED_NODE_COUNT" =~ ^[0-9]+$ ]] && [ "$nodes_in_cluster" -ne "$EXPECTED_NODE_COUNT" ]; then
    log_with_timestamp "nodes_in_cluster=$nodes_in_cluster differs from EXPECTED_NODE_COUNT=$EXPECTED_NODE_COUNT. Will try to join $${CURRENT_NODE_NAME}."
    should_join=true
  fi

  # If neither condition is true, don't touch the cluster
  if [ "$should_join" = false ]; then
    log_with_timestamp "No disconnected nodes (graphdb_nodes_disconnected=$disconnected_nodes) and nodes_in_cluster=$nodes_in_cluster matches EXPECTED_NODE_COUNT=$EXPECTED_NODE_COUNT. Skipping join_cluster for $${CURRENT_NODE_NAME}."
    return 0
  fi

  log_with_timestamp "Trying to delete $CURRENT_NODE_NAME"
  # Removes node if already present in the cluster config
  gdb_curl -X DELETE -s \
    --fail-with-body \
    -o "/dev/null" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -w "%%{http_code}" \
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
      gdb_curl -X POST -s \
        -m $CURL_MAX_REQUEST_TIME \
        -o "/dev/null" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -w "%%{http_code}" \
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

if [ ! -d "$RAFT_DIR" ]; then
  log_with_timestamp "Raft directory $RAFT_DIR not found, joining the current node to the cluster"
  join_cluster
else
  log_with_timestamp "Found Raft directory"
  if [ -z "$(ls -A "$RAFT_DIR")" ]; then
    log_with_timestamp "Found $RAFT_DIR folder, but it is empty. joining the current node to the cluster"
    join_cluster
  fi
fi

echo "###########################"
echo "#    Script completed     #"
echo "###########################"
