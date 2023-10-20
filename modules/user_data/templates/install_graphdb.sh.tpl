#!/usr/bin/env bash

set -euxo pipefail

until ping -c 1 google.com &> /dev/null; do
  echo "waiting for outbound connectivity"
  sleep 5
done

timedatectl set-timezone UTC

# install tools

apt-get update
apt-get -o DPkg::Lock::Timeout=300 install -y unzip jq nvme-cli openjdk-11-jdk bash-completion

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf ./awscliv2.zip ./aws

# Create the GraphDB user

useradd --comment "GraphDB Service User" --create-home --system --shell /bin/bash --user-group graphdb

# Create GraphDB directories

mkdir -p /var/opt/graphdb/data /var/opt/graphdb/logs /etc/graphdb /etc/graphdb-cluster-proxy /var/opt/graphdb-cluster-proxy/logs

# Set common variables used throughout the script.
imds_token=$( curl -Ss -H "X-aws-ec2-metadata-token-ttl-seconds: 300" -XPUT 169.254.169.254/latest/api/token )
local_ipv4=$( curl -Ss -H "X-aws-ec2-metadata-token: $imds_token" 169.254.169.254/latest/meta-data/local-ipv4 )
instance_id=$( curl -Ss -H "X-aws-ec2-metadata-token: $imds_token" 169.254.169.254/latest/meta-data/instance-id )
availability_zone=$( curl -Ss -H "X-aws-ec2-metadata-token: $imds_token" 169.254.169.254/latest/meta-data/placement/availability-zone )
volume_id=""

# Search for an available EBS volume to attach to the instance. Wait one minute for a volume to become available,
# if no volume is found - create new one, attach, format and mount the volume.

for i in $(seq 1 6); do

  volume_id=$(
    aws --cli-connect-timeout 300 ec2 describe-volumes \
      --filters "Name=status,Values=available" "Name=availability-zone,Values=$availability_zone" "Name=tag:Name,Values=${name}-graphdb-data" \
      --query "Volumes[*].{ID:VolumeId}" \
      --output text | \
      sed '/^$/d'
  )

  if [ -z "$${volume_id:-}" ]; then
    echo 'ebs volume not yet available'
    sleep 10
  else
    break
  fi
done

if [ -z "$${volume_id:-}" ]; then

  volume_id=$(
    aws --cli-connect-timeout 300 ec2 create-volume \
      --availability-zone "$availability_zone" \
      --encrypted \
      --kms-key-id "${ebs_kms_key_arn}" \
      --volume-type "${ebs_volume_type}" \
      --size "${ebs_volume_size}" \
      --iops "${ebs_volume_iops}" \
      --throughput "${ebs_volume_throughput}" \
      --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${name}-graphdb-data}]" | \
      jq -r .VolumeId
  )

  aws --cli-connect-timeout 300 ec2 wait volume-available --volume-ids "$volume_id"
fi

aws --cli-connect-timeout 300 ec2 attach-volume \
  --volume-id "$volume_id" \
  --instance-id "$instance_id" \
  --device "${device_name}"

# Handle the EBS volume used for the GraphDB data directory
# beware, here be dragons...
# read these articles:
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/device_naming.html
# https://github.com/oogali/ebs-automatic-nvme-mapping/blob/master/README.md

# this variable comes from terraform, and it's what we specified in the launch template as the device mapping for the ebs
# because this might be attached under a different name, we'll need to search for it
device_mapping_full="${device_name}"
device_mapping_short="$(echo $device_mapping_full | cut -d'/' -f3)"

graphdb_device=""

# the device might not be available immediately, wait a while
for i in $(seq 1 12); do
  for volume in $(find /dev | grep -i 'nvme[0-21]n1$'); do
    # extract the specified device from the vendor-specific data
    # read https://github.com/oogali/ebs-automatic-nvme-mapping/blob/master/README.md, for more information
    real_device=$(nvme id-ctrl --raw-binary $volume | cut -c3073-3104 | tr -s ' ' | sed 's/ $//g')
    if [ "$device_mapping_full" = "$real_device" ] || [ "$device_mapping_short" = "$real_device" ]; then
      graphdb_device="$volume"
      break
    fi
  done

  if [ -n "$graphdb_device" ]; then
    break
  fi
  sleep 5
done

# create a file system if there isn't any
if [ "$graphdb_device: data" = "$(file -s $graphdb_device)" ]; then
  mkfs -t ext4 $graphdb_device
fi

mount $graphdb_device /var/opt/graphdb/data

# Register the instance in Route 53, using the volume id for the sub-domain

subdomain="$( echo -n "$volume_id" | sed 's/^vol-//' )"
node_dns="$subdomain.${zone_dns_name}"

aws --cli-connect-timeout 300 route53 change-resource-record-sets \
  --hosted-zone-id "${zone_id}" \
  --change-batch '{"Changes": [{"Action": "UPSERT","ResourceRecordSet": {"Name": "'"$node_dns"'","Type": "A","TTL": 60,"ResourceRecords": [{"Value": "'"$local_ipv4"'"}]}}]}'

hostnamectl set-hostname "$node_dns"

# Configure GraphDB

aws --cli-connect-timeout 300 ssm get-parameter --region ${region} --name "/${name}/graphdb/license" --with-decryption | \
  jq -r .Parameter.Value | \
  base64 -d > /etc/graphdb/graphdb.license

graphdb_cluster_token="$(aws --cli-connect-timeout 300 ssm get-parameter --region ${region} --name "/${name}/graphdb/cluster_token" --with-decryption | jq -r .Parameter.Value)"

cat << EOF > /etc/graphdb/graphdb.properties
graphdb.home.data=/var/opt/graphdb/data
graphdb.home.logs=/var/opt/graphdb/logs

graphdb.page.cache.size=10g

graphdb.auth.token.secret=$graphdb_cluster_token

graphdb.connector.port=7201
graphdb.external-url=http://$${node_dns}:7201/
graphdb.rpc.address=$${node_dns}:7301

EOF

load_balancer_dns=$(aws --cli-connect-timeout 300 ssm get-parameter --region ${region} --name "/${name}/graphdb/lb_dns_name" | jq -r .Parameter.Value)

cat << EOF > /etc/graphdb-cluster-proxy/graphdb.properties
graphdb.home.logs=/var/opt/graphdb-cluster-proxy/logs

graphdb.auth.token.secret=$graphdb_cluster_token

graphdb.connector.port=7200

graphdb.external-url=http://$${load_balancer_dns}
graphdb.vhosts=http://$${load_balancer_dns},http://$${node_dns}
graphdb.rpc.address=$${node_dns}:7300

graphdb.proxy.hosts=$${node_dns}:7301

EOF

# Configure the GraphDB backup cron job

cat <<-EOF > /usr/bin/graphdb_backup
#!/bin/bash

set -euxo pipefail

GRAPHDB_ADMIN_PASSWORD="\$(aws --cli-connect-timeout 300 ssm get-parameter --region ${region} --name "/${name}/graphdb/admin_password" --with-decryption | jq -r .Parameter.Value)"
NODE_STATE="\$(curl --silent --fail --user "admin:\$GRAPHDB_ADMIN_PASSWORD" localhost:7200/rest/cluster/node/status | jq -r .nodeState)"

if [ "\$NODE_STATE" != "LEADER" ]; then
  echo "current node is not a leader, but \$NODE_STATE"
  exit 0
fi

function trigger_backup {
  local backup_name="\$(date +'%Y-%m-%d_%H-%M-%S').tar"

  curl \
    -vvv --fail \
    --user "admin:\$GRAPHDB_ADMIN_PASSWORD" \
    --url localhost:7200/rest/recovery/cloud-backup \
    --header 'Content-Type: application/json' \
    --header 'Accept: application/json' \
    --data-binary @- <<-DATA
    {
      "backupOptions": { "backupSystemData": true },
      "bucketUri": "s3:///${name}-graphdb-backup/\$backup_name?region=${region}&AWS_ACCESS_KEY_ID=${backup_iam_key_id}&AWS_SECRET_ACCESS_KEY=${backup_iam_key_secret}"
    }
DATA
}

function rotate_backups {
  all_files="\$(aws --cli-connect-timeout 300 s3api list-objects --bucket ${name}-graphdb-backup --query 'Contents' | jq .)"
  count="\$(echo \$all_files | jq length)"
  delete_count="\$((count - ${backup_retention_count} - 1))"

  for i in \$(seq 0 \$delete_count); do
    key="\$(echo \$all_files | jq -r .[\$i].Key)"

    aws --cli-connect-timeout 300 s3 rm s3://${name}-graphdb-backup/\$key
  done
}

if ! trigger_backup; then
  echo "failed to create backup"
  exit 1
fi

rotate_backups

EOF

chmod +x /usr/bin/graphdb_backup
echo "${backup_schedule} graphdb /usr/bin/graphdb_backup" > /etc/cron.d/graphdb_backup

# Install GraphDB

# https://docs.aws.amazon.com/elasticloadbalancing/latest/network/network-load-balancers.html#connection-idle-timeout
echo 'net.ipv4.tcp_keepalive_time = 120' | tee -a /etc/sysctl.conf
echo 'fs.file-max = 262144' | tee -a /etc/sysctl.conf

sysctl -p

cd /tmp
# sometimes host cannot be resolved
until curl -O https://maven.ontotext.com/repository/owlim-releases/com/ontotext/graphdb/graphdb/${graphdb_version}/graphdb-${graphdb_version}-dist.zip; do
  sleep 5
done

unzip graphdb-${graphdb_version}-dist.zip
rm graphdb-${graphdb_version}-dist.zip
mv graphdb-${graphdb_version} /opt/graphdb-${graphdb_version}
ln -s /opt/graphdb-${graphdb_version} /opt/graphdb

chown -R graphdb:graphdb /var/opt/graphdb/data /var/opt/graphdb/logs /etc/graphdb /opt/graphdb /opt/graphdb-${graphdb_version} /etc/graphdb-cluster-proxy /var/opt/graphdb-cluster-proxy/logs

cat << EOF > /lib/systemd/system/graphdb.service
[Unit]
Description="GraphDB Engine"
Wants=network-online.target
After=network-online.target

[Service]
Restart=on-failure
RestartSec=5s
User=graphdb
Group=graphdb
Environment="GDB_JAVA_OPTS=-Xmx30g -Dgraphdb.home.conf=/etc/graphdb -Dhttp.socket.keepalive=true"
ExecStart="/opt/graphdb/bin/graphdb"
TimeoutSec=120
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /lib/systemd/system/graphdb-cluster-proxy.service
[Unit]
Description="GraphDB Cluster Proxy"
Wants=network-online.target
After=network-online.target

[Service]
Restart=on-failure
RestartSec=5s
User=graphdb
Group=graphdb
Environment="GDB_JAVA_OPTS=-Dgraphdb.home.conf=/etc/graphdb-cluster-proxy -Dhttp.socket.keepalive=true"
ExecStart="/opt/graphdb/bin/cluster-proxy"
TimeoutSec=120
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable graphdb.service
systemctl start graphdb.service

systemctl enable graphdb-cluster-proxy.service
systemctl start graphdb-cluster-proxy.service
