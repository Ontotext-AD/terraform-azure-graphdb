#!/bin/bash

set -euxo pipefail

#
# Change admin user password and enable security
#

GRAPHDB_ADMIN_PASSWORD="$(az keyvault secret show --vault-name ${key_vault_name} --name graphdb-password --query "value" --output tsv)"
SECURITY_ENABLED=$(curl -s -X GET --header 'Accept: application/json' -u "admin:$${GRAPHDB_ADMIN_PASSWORD}" 'http://localhost:7200/rest/security')

# Check if GDB security is enabled
if [[ $SECURITY_ENABLED == "true" ]]; then
  echo "Security is enabled"
else
  # Set the admin password
  curl --location --request PATCH 'http://localhost:7200/rest/security/users/admin' \
    --header 'Content-Type: application/json' \
    --data "{ \"password\": \"$${GRAPHDB_ADMIN_PASSWORD}\" }"
  # Enable the security
  curl -X POST --header 'Content-Type: application/json' --header 'Accept: */*' -d 'true' 'http://localhost:7200/rest/security'
fi
