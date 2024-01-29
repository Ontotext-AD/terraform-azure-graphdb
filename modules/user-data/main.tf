data "cloudinit_config" "entrypoint" {
  base64_encode = true
  gzip          = false

  part {
    content_type = "text/x-shellscript"
    content      = <<-EOF
        #!/bin/bash
        # Stop GraphDB to override configurations
        echo "Stopping GraphDB"
        systemctl stop graphdb
        az login --identity
      EOF
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/01_disk_management.sh.tpl", {
      disk_storage_account_type : var.disk_storage_account_type
      disk_iops_read_write : var.disk_iops_read_write
      disk_mbps_read_write : var.disk_mbps_read_write
      disk_size_gb : var.disk_size_gb
      disk_network_access_policy : var.disk_network_access_policy
      disk_public_network_access : var.disk_public_network_access
    })
  }

  part {
    content_type = "text/x-shellscript"
    content      = templatefile("${path.module}/templates/02_dns_provisioning.sh.tpl", {})
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/03_gdb_conf_overrides.sh.tpl", {
      graphdb_external_address_fqdn : var.graphdb_external_address_fqdn
      app_config_name : var.app_configuration_name
    })
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/04_gdb_backup_conf.sh.tpl", {
      app_config_name : var.app_configuration_name
      backup_schedule : var.backup_schedule
      backup_storage_account_name : var.backup_storage_account_name
      backup_storage_container_name : var.backup_storage_container_name
    })
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/05_telegraf_conf.sh.tpl", {
      app_config_name : var.app_configuration_name
    })
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/06_cluster_setup.sh.tpl", {
      app_config_name : var.app_configuration_name
    })
  }

}
