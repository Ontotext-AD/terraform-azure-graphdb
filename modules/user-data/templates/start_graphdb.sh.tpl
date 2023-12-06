#!/bin/bash

set -euxo pipefail

systemctl daemon-reload
systemctl start graphdb
systemctl enable graphdb-cluster-proxy.service
systemctl start graphdb-cluster-proxy.service
