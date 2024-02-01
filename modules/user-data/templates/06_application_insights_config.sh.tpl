#!/bin/bash

set -euo pipefail

echo "###########################################"
echo "#    Configuring Application Insights     #"
echo "###########################################"


# Overrides the config file
cat <<-EOF > /opt/graphdb/applicationinsights.json
{
  "connectionString": "${appi_connection_string}"
}
EOF

chown graphdb:graphdb /opt/graphdb/applicationinsights.json
