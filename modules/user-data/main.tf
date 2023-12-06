# See https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/cloudinit_config
data "template_file" "entrypoint" {
  template = "${file("${path.module}/templates/entrypoint.sh.tpl")}"

  vars = {
    key_vault_name = var.key_vault_name
  }
}

data template_file "disk_create" {
  template = "${file("${path.module}/templates/disk_create.sh.tpl")}"

  vars = {
    disk_iops_read_write = var.disk_iops_read_write
    disk_mbps_read_write = var.disk_mbps_read_write
    disk_size_gb         = var.disk_size_gb
  }
}

data template_file "set_dns_records_and_configs" {
  template = "${file("${path.module}/templates/set_dns_records_and_configs.sh.tpl")}"

  vars = {
    key_vault_name                = var.key_vault_name
    graphdb_external_address_fqdn = var.graphdb_external_address_fqdn
  }
}

data template_file "setup_backup_script" {
  template = "${file("${path.module}/templates/setup_backup_script.sh.tpl")}"

  vars = {
    key_vault_name                = var.key_vault_name
    backup_storage_account_name   = var.backup_storage_account_name
    backup_storage_container_name = var.backup_storage_container_name
    backup_schedule               = var.backup_schedule
  }
}

data template_file "start_graphdb" {
  template = "${file("${path.module}/templates/start_graphdb.sh.tpl")}"
}

data template_file "setup_cluster" {
  template = "${file("${path.module}/templates/setup_cluster.sh.tpl")}"

  vars = {
    key_vault_name = var.key_vault_name
  }
}

data template_file "enable_security" {
  template = "${file("${path.module}/templates/enable_security.sh.tpl")}"

  vars = {
    key_vault_name = var.key_vault_name
  }
}

data "template_cloudinit_config" "userdata" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.entrypoint.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.disk_create.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.set_dns_records_and_configs.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.setup_backup_script.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.start_graphdb.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.setup_cluster.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.enable_security.rendered
  }
}
