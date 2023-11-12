#!/usr/bin/env bash

set -euxo pipefail

echo "Configuring GraphDB instance"

systemctl stop graphdb

# TODO: If GraphDB is behind closed network, this would break the whole initialization...
until ping -c 1 google.com &> /dev/null; do
  echo "waiting for outbound connectivity"
  sleep 5
done

# Login in Azure CLI with managed identity (user or system assigned)
az login --identity

# TODO: Find/create/mount volumes
# https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/tutorial-use-disks-cli

#
# DNS hack
#

# TODO: Should be based on something stable, e.g. volume id
node_dns=$(hostname)

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
graphdb.external-url=http://${load_balancer_fqdn}
graphdb.vhosts=http://${load_balancer_fqdn},http://$${node_dns}:7201
graphdb.rpc.address=$${node_dns}:7301
graphdb.proxy.hosts=$${node_dns}:7300
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

# TODO: -Xmx based on the machine's memory size

# TODO: Backup cron

# TODO: Monitoring/instrumenting

systemctl daemon-reload
systemctl start graphdb
systemctl enable graphdb-cluster-proxy.service
systemctl start graphdb-cluster-proxy.service

echo "Finished GraphDB instance configuration"
