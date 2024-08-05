#!/bin/bash

# This script focuses on configuring Application Insights
#
# It performs the following tasks:
# * Provisions /opt/graphdb/applicationinsights.json
# * Changes the owner of applicationinsights.json to graphdb

# Imports helper functions
source /var/lib/cloud/instance/scripts/part-002

set -o errexit
set -o nounset
set -o pipefail

echo "###########################################"
echo "#    Configuring Application Insights     #"
echo "###########################################"

if [ ! -f /var/opt/graphdb/node_dns_name ]; then
  RECORD_NAME=${resource_name_prefix}
else
  RECORD_NAME=$(cat /var/opt/graphdb/node_dns_name)
fi

# Overrides the config file
cat <<-EOF >/opt/graphdb/applicationinsights.json
{
    "role": {
        "name": "$RECORD_NAME"
      },
    "connectionString": "${appi_connection_string}",
    "sampling": {
      "percentage": ${appi_sampling_percentage}
  },
    "instrumentation": {
        "logging": {
            "level": "${appi_logging_level}"
        }
    },
    "preview": {
        "captureLogbackMarker": true,
        "captureLog4jMarker": true,
        "captureLogbackCodeAttributes": true,
        "sampling": {
            "overrides": [
              {
                "telemetryType": "dependency",
                "percentage": ${appi_dependency_sampling_override}
              },
              {
                "telemetryType": "request",
                "percentage": ${appi_grpc_sampling_override},
                "attributes": [
                   {
                     "key": "rpc.service",
                     "value": ".*cluster.*",
                     "matchType":  "regexp"
                   }
                ]
              },
              {
                "telemetryType": "request",
                "percentage": 0,
                "attributes": [
                   {
                     "key": "http.url",
                     "value": "https?://[^/]+/(res|i18n|js|css|img|pages)/.*",
                     "matchType": "regexp"
                   }
                ]
              },
              {
                "telemetryType": "request",
                "percentage": 0,
                "attributes": [
                   {
                     "key": "http.url",
                     "value": "https?://[^/]+/.*(cluster|namespaces|status|locations.*|license.*|acl|monitor.*|autocomplete.*|cluster.*|saved-queries|security.*|version.*|all|connectors.*|info.*|rdfrank.*|/sql-views.*|protocol)",
                     "matchType": "regexp"
                   }
                ]
              },
              {
                "telemetryType": "request",
                "percentage": ${appi_repositories_requests_sampling},
                "attributes": [
                   {
                     "key": "http.url",
                     "value": "https?://[^/]+/(repositories)/.*",
                     "matchType": "regexp"
                   }
                ]
              },
              {
                "telemetryType": "request",
                "percentage": 100,
                "attributes": [
                   {
                     "key": "http.url",
                     "value": "https?://[^/]+/(rest/recovery)/.*",
                     "matchType": "regexp"
                   }
                ]
              },
              {
                "telemetryType": "request",
                "percentage": 0,
                "attributes": [
                   {
                     "key": "http.url",
                     "value": ".*/[^/]+.(js|css|html|woff2|png|svg|gif|favicon).*",
                     "matchType": "regexp"
                   }
                ]
              }
            ]
        }
    }
}

EOF

chown graphdb:graphdb /opt/graphdb/applicationinsights.json

log_with_timestamp "Finished configuring Application Insights Agent"
