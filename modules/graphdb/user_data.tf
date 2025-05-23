#
# User data script
#

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

  # 00 Helper functions
  part {
    content_type = "text/x-shellscript"
    content      = templatefile("${path.module}/templates/00_functions.sh", {})
  }


  # 01 Wait for dependent resources
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/01_wait_resources.sh.tpl", {
      private_dns_zone_name : azurerm_private_dns_zone.graphdb.name
      private_dns_zone_id : azurerm_private_dns_zone.graphdb.id
      private_dns_zone_link_name : azurerm_private_dns_zone_virtual_network_link.graphdb.name
      private_dns_zone_link_id : azurerm_private_dns_zone_virtual_network_link.graphdb.id
      app_configuration_endpoint : var.app_configuration_endpoint
      app_configuration_id : var.app_configuration_id
      storage_account_name : var.backup_storage_account_name
      vmss_name : "vmss-${var.resource_name_prefix}"
      resource_group : var.resource_group_name
    })
  }

  # 02 Disk setup
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/02_disk_management.sh.tpl", {
      resource_name_prefix : var.resource_name_prefix
      disk_storage_account_type : var.disk_storage_account_type
      disk_iops_read_write : var.disk_iops_read_write
      disk_mbps_read_write : var.disk_mbps_read_write
      disk_size_gb : var.disk_size_gb
      disk_network_access_policy : var.disk_network_access_policy
      disk_public_network_access : var.disk_public_network_access
    })
  }

  # 03 DNS setup
  dynamic "part" {
    for_each = var.node_count > 1 ? [1] : []

    content {
      content_type = "text/x-shellscript"
      content = templatefile("${path.module}/templates/03_dns_provisioning.sh.tpl", {
        private_dns_zone_name : azurerm_private_dns_zone.graphdb.name
      })
    }
  }

  # 04 GDB config overrides
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/04_gdb_conf_overrides.sh.tpl", {
      graphdb_external_address_fqdn : var.graphdb_external_address_fqdn
      private_dns_zone_name : azurerm_private_dns_zone.graphdb.name
      # App configurations
      app_configuration_endpoint : var.app_configuration_endpoint
      graphdb_license_secret_name : var.graphdb_license_secret_name
      graphdb_cluster_token_name : var.graphdb_cluster_token_name
      graphdb_password_secret_name : var.graphdb_password_secret_name
      graphdb_properties_secret_name : var.graphdb_properties_secret_name
      graphdb_java_options_secret_name : var.graphdb_java_options_secret_name
      context_path : var.context_path
      disable_agw : var.disable_agw
    })
  }

  # 05 Backup script configuration
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/05_gdb_backup_conf.sh.tpl", {
      app_configuration_endpoint : var.app_configuration_endpoint
      backup_schedule : var.backup_schedule
      backup_storage_account_name : var.backup_storage_account_name
      backup_storage_container_name : var.backup_storage_container_name
    })
  }

  # 06 Telegraf configuration
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/06_telegraf_conf.sh.tpl", {
      app_configuration_endpoint : var.app_configuration_endpoint
    })
  }

  # 07 Application Insights configuration
  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/07_application_insights_config.sh.tpl", {
      appi_connection_string : var.appi_connection_string
      appi_sampling_percentage : var.appi_sampling_percentage
      appi_logging_level : var.appi_logging_level
      appi_dependency_sampling_override : var.appi_dependency_sampling_override
      appi_grpc_sampling_override : var.appi_grpc_sampling_override
      appi_repositories_requests_sampling : var.appi_repositories_requests_sampling
      resource_name_prefix : var.resource_name_prefix
    })
  }

  # 08 Cluster setup
  dynamic "part" {
    for_each = var.node_count > 1 ? [1] : []
    content {
      content_type = "text/x-shellscript"
      content = templatefile("${path.module}/templates/08_cluster_setup.sh.tpl", {
        app_configuration_endpoint : var.app_configuration_endpoint
        private_dns_zone_name : azurerm_private_dns_zone.graphdb.name
      })
    }
  }

  # 09 Cluster rejoin
  dynamic "part" {
    for_each = var.node_count > 1 ? [1] : []
    content {
      content_type = "text/x-shellscript"
      content = templatefile("${path.module}/templates/09_cluster_join.sh.tpl", {
        app_configuration_endpoint : var.app_configuration_endpoint
      })
    }
  }

  # 10 Start GDB services - Single node
  dynamic "part" {
    for_each = var.node_count == 1 ? [1] : []
    content {
      content_type = "text/x-shellscript"
      content = templatefile("${path.module}/templates/10_start_single_graphdb_services.sh.tpl", {
        app_configuration_endpoint : var.app_configuration_endpoint
        private_dns_zone_name : azurerm_private_dns_zone.graphdb.name
      })
    }
  }

  # 11 Execute additional scripts
  dynamic "part" {
    for_each = var.user_supplied_scripts
    content {
      content_type = "text/x-shellscript"
      content      = file(part.value)
    }
  }

  # 12 Execute additional rendered templates
  dynamic "part" {
    for_each = var.user_supplied_rendered_templates
    content {
      content_type = "text/x-shellscript"
      content      = part.value
    }
  }

  # 13 Execute additional templates
  dynamic "part" {
    for_each = var.user_supplied_templates
    content {
      content_type = "text/x-shellscript"
      content      = templatefile(part.value["path"], part.value["variables"])
    }
  }

  part {
    content_type = "text/x-shellscript"
    content      = <<-EOF
        #!/bin/bash
        [[ -f /etc/sudoers.d/90-cloud-init-users ]] && rm /etc/sudoers.d/90-cloud-init-users
      EOF
  }
}
