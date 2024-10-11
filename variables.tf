# General configurations

variable "resource_group_name" {
  description = "The name of the existing resource group to use. If not provided, a new resource group will be created."
  type        = string
  default     = null
}

variable "virtual_network_name" {
  description = "The name of the existing vnet to use. If not provided, a new virtual network will be created."
  type        = string
  default     = null
}

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,24}$", var.resource_name_prefix)) && !can(regex("^-", var.resource_name_prefix))
    error_message = "Resource name prefix cannot start with a hyphen and can only contain letters, numbers, hyphens and have a length between 2 and 24."
  }
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "zones" {
  description = "Availability zones to use for resource deployment and HA"
  type        = list(number)
  default     = [1, 2, 3]
}

variable "tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "lock_resources" {
  description = "Enables a delete lock on the resource group to prevent accidental deletions."
  type        = bool
  default     = true
}

# Networking

variable "vmss_dns_servers" {
  description = "List of DNS servers for the VMSS"
  type        = list(string)
  default     = []
}

variable "graphdb_external_address_fqdn" {
  description = "External FQDN address for the deployment"
  type        = string
  default     = null
}

variable "virtual_network_address_space" {
  description = "Virtual network address space CIDRs."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "gateway_subnet_address_prefixes" {
  description = "Subnet address prefixes CIDRs where the application gateway will reside."
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "graphdb_subnet_address_prefixes" {
  description = "Subnet address prefixes CIDRs where GraphDB VMs will reside."
  type        = list(string)
  default     = ["10.0.2.0/24"]
}

variable "gateway_private_link_subnet_address_prefixes" {
  description = "Subnet address prefixes where the Application Gateway Private Link will reside, if enabled"
  type        = list(string)
  default     = ["10.0.5.0/24"]
}

variable "management_cidr_blocks" {
  description = "CIDR blocks allowed to perform management operations such as connecting to Bastion or Key Vault."
  type        = list(string)
}

# Inbound/Outbound network security rules
# Note that these should be taken into considerations when gateway_enable_private_access=true

variable "inbound_allowed_address_prefix" {
  description = "Source address prefix allowed for connecting to the application gateway"
  type        = string
  default     = "Internet"
}

variable "inbound_allowed_address_prefixes" {
  description = "Source address prefixes allowed for connecting to the application gateway. Overrides inbound_allowed_address_prefix"
  type        = list(string)
  default     = []
}

variable "outbound_allowed_address_prefix" {
  description = "Destination address prefix allowed for outbound traffic from GraphDB"
  type        = string
  default     = "Internet"
}

variable "outbound_allowed_address_prefixes" {
  description = "Destination address prefixes allowed for outbound traffic from GraphDB. Overrides outbound_allowed_address_prefix"
  type        = list(string)
  default     = []
}

# Application Gateway & Private Link Configurations

# Application Gateway Global Proxy buffer configurations
variable "gateway_global_request_buffering_enabled" {
  description = "Whether Application Gateway's Request buffer is enabled."
  type        = bool
  default     = true
}

variable "gateway_global_response_buffering_enabled" {
  description = "Whether Application Gateway's Response buffer is enabled."
  type        = bool
  default     = true
}

variable "gateway_enable_private_access" {
  description = "Enable or disable private access to the application gateway"
  type        = bool
  default     = false
}

variable "gateway_enable_private_link_service" {
  description = "Set to true to enable Private Link service, false to disable it."
  type        = bool
  default     = false
}

variable "gateway_private_link_service_network_policies_enabled" {
  description = "Enable or disable private link service network policies"
  type        = string
  default     = false
}

variable "gateway_backend_port" {
  description = "Backend port for the Application Gateway rules"
  type        = number
  default     = 7201
}

variable "gateway_probe_interval" {
  description = "Interval in seconds between the health probe checks"
  type        = number
  default     = 10
}

variable "gateway_probe_timeout" {
  description = "Timeout in seconds for the health probe checks"
  type        = number
  default     = 1
}

variable "gateway_probe_threshold" {
  description = "Number of consecutive health checks to consider the probe passing or failing"
  type        = number
  default     = 2
}

# TLS
variable "tls_certificate_path" {
  description = "Path to a TLS certificate that will be imported in Azure Key Vault and used in the Application Gateway TLS listener for GraphDB. Either tls_certificate_path or tls_certificate_password must be provided."
  type        = string
}

variable "tls_certificate_password" {
  description = "TLS certificate password for password-protected certificates. Either tls_certificate_password or tls_certificate_path must be provided"
  type        = string
  default     = null
}

variable "tls_certificate_id" {
  description = "Resource identifier for a TLS certificate secret from a Key Vault. Overrides tls_certificate_path"
  type        = string
  default     = null
}

variable "tls_certificate_identity_id" {
  description = "Identifier of a managed identity giving access to the TLS certificate specified with tls_certificate_id"
  type        = string
  default     = null
}

# Key Vault

variable "key_vault_enable_purge_protection" {
  description = "Prevents purging the key vault and its contents by soft deleting it. It will be deleted once the soft delete retention has passed."
  type        = bool
  default     = true
}

variable "key_vault_soft_delete_retention_days" {
  description = "Retention period in days during which soft deleted secrets are kept"
  type        = number
  default     = 30
  validation {
    condition     = var.key_vault_soft_delete_retention_days >= 7 && var.key_vault_soft_delete_retention_days <= 90
    error_message = "Key Vault soft delete retention days must be between 7 and 90 (inclusive)"
  }
}

# App Configuration

variable "app_config_enable_purge_protection" {
  description = "Prevents purging the App Configuration and its keys by soft deleting it. It will be deleted once the soft delete retention has passed."
  type        = bool
  default     = true
}

variable "app_config_soft_delete_retention_days" {
  description = "Retention period in days during which soft deleted keys are kept"
  type        = number
  default     = 7
  validation {
    condition     = var.app_config_soft_delete_retention_days >= 1 && var.app_config_soft_delete_retention_days <= 7
    error_message = "App Configuration soft delete retention days must be between 1 and 7 (inclusive)"
  }
}

# Role Assignments

variable "admin_security_principle_id" {
  description = "UUID of a user or service principle that will become data owner or administrator for specific resources that need permissions to insert data during Terraform apply, i.e. KeyVault and AppConfig. If left unspecified, the current user will be used."
  type        = string
  default     = null
}

# GraphDB VM image configuration

variable "graphdb_version" {
  description = "GraphDB version from the marketplace offer"
  type        = string
  default     = "10.7.4"
}

variable "graphdb_sku" {
  description = "GraphDB SKU from the marketplace offer"
  type        = string
  default     = "graphdb-byol"
}

variable "graphdb_image_id" {
  description = "GraphDB image ID to use for the scale set VM instances in place of the default marketplace offer"
  type        = string
  default     = null
}

# GraphDB configurations

variable "graphdb_license_path" {
  description = "Local path to a file, containing a GraphDB Enterprise license."
  type        = string
}

variable "graphdb_cluster_token" {
  description = "Secret token used to secure the internal GraphDB cluster communication. Will generate one if left undeclared."
  type        = string
  default     = null
  sensitive   = true
}

variable "graphdb_password" {
  description = "Secret token used to access GraphDB cluster."
  type        = string
  default     = null
  sensitive   = true
}

variable "graphdb_properties_path" {
  description = "Path to a local file containing GraphDB properties (graphdb.properties) that would be appended to the default in the VM."
  type        = string
  default     = null
}

variable "graphdb_java_options" {
  description = "GraphDB options to pass to GraphDB with GRAPHDB_JAVA_OPTS environment variable."
  type        = string
  default     = null
}

# GraphDB VM

variable "node_count" {
  description = "Number of GraphDB nodes to deploy in ASG"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "Azure instance type"
  type        = string
}

variable "ssh_key" {
  description = "Public key for accessing the GraphDB instances"
  type        = string
  default     = null
}

# Customer provided user data scripts
variable "user_supplied_scripts" {
  description = "Array of additional shell scripts to execute sequentially after the templated user data shell scripts."
  type        = list(string)
  default     = []
}

# Storage account, primarily used for GraphDB backups

variable "storage_account_tier" {
  description = "Specify the performance and redundancy characteristics of the Azure Storage Account that you are creating"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Specify the data redundancy strategy for your Azure Storage Account"
  type        = string
  default     = "ZRS"
}

variable "storage_blobs_max_days_since_creation" {
  description = "Specifies the retention period in days since creation before deleting storage blobs"
  type        = number
  default     = 31
}

variable "storage_account_retention_hot_to_cool" {
  description = "Specifies the retention period in days between moving data from hot to cool tier storage"
  type        = number
  default     = 3
}

variable "storage_container_soft_delete_retention_policy" {
  description = "Number of days for retaining the storage container from actual deletion"
  type        = number
  default     = 31
  validation {
    condition     = var.storage_container_soft_delete_retention_policy >= 1 && var.storage_container_soft_delete_retention_policy <= 365
    error_message = "Storage container soft delete retention days must be between 1 and 365 (inclusive)"
  }
}

variable "storage_blob_soft_delete_retention_policy" {
  description = "Number of days for retaining storage blobs from actual deletion"
  type        = number
  default     = 31
  validation {
    condition     = var.storage_blob_soft_delete_retention_policy >= 1 && var.storage_blob_soft_delete_retention_policy <= 365
    error_message = "Storage blobs soft delete retention days must be between 1 and 365 (inclusive)"
  }
}

# Backup configurations

variable "backup_schedule" {
  description = "Cron expression for the backup job."
  type        = string
  default     = "0 0 * * *"
}

# Bastion

variable "deploy_bastion" {
  description = "Deploy bastion module"
  type        = bool
  default     = false
}

variable "bastion_subnet_address_prefixes" {
  description = "Bastion subnet address prefixes"
  type        = list(string)
  default     = ["10.0.3.0/26"]
}

# Monitoring

variable "deploy_monitoring" {
  description = "Deploy monitoring module"
  type        = bool
  default     = true
}

# Managed disks

variable "disk_size_gb" {
  description = "Size of the managed data disk which will be created"
  type        = number
  default     = 500
}

variable "disk_iops_read_write" {
  description = "Data disk IOPS"
  type        = number
  default     = 7500
}

variable "disk_mbps_read_write" {
  description = "Data disk throughput"
  type        = number
  default     = 250
}

variable "disk_storage_account_type" {
  description = "Storage account type for the data disks"
  type        = string
  default     = "PremiumV2_LRS"
}

variable "disk_network_access_policy" {
  description = "Network accesss policy for the managed disks"
  type        = string
  default     = "DenyAll"
}

variable "disk_public_network_access" {
  description = "Public network access enabled for the managed disks"
  type        = bool
  default     = false
}

# APPI related variables

variable "la_workspace_retention_in_days" {
  description = "The workspace data retention in days. Possible values are either 7 (Free Tier only) or range between 30 and 730."
  type        = number
  default     = 30
}

variable "la_workspace_sku" {
  description = "Specifies the SKU of the Log Analytics Workspace. Possible values are Free, PerNode, Premium, Standard, Standalone, Unlimited, CapacityReservation, and PerGB2018 (new SKU as of 2018-04-03). Defaults to PerGB2018."
  type        = string
  default     = "PerGB2018"
}

variable "appi_retention_in_days" {
  description = "Specifies the retention period in days."
  type        = number
  default     = 30
}

variable "appi_daily_data_cap_in_gb" {
  description = "Specifies the Application Insights component daily data volume cap in GB."
  type        = number
  default     = 1
}

variable "appi_daily_data_cap_notifications_disabled" {
  description = "Specifies if a notification email will be send when the daily data volume cap is met."
  type        = bool
  default     = false
}

variable "appi_disable_ip_masking" {
  description = "By default the real client IP is masked as 0.0.0.0 in the logs. Use this argument to disable masking and log the real client IP"
  type        = bool
  default     = true
}

variable "appi_web_test_availability_enabled" {
  description = "Should the availability web test be enabled"
  type        = bool
  default     = true
}

# TODO change to true if prod deployment
variable "web_test_ssl_check_enabled" {
  description = "Should the SSL check be enabled?"
  type        = bool
  default     = false
}

variable "web_test_geo_locations" {
  description = "A list of geo locations the test will be executed from"
  type        = list(string)
  default     = ["us-va-ash-azr", "us-il-ch1-azr", "emea-gb-db3-azr", "emea-nl-ams-azr", "apac-hk-hkn-azr"]
}

variable "monitor_reader_principal_id" {
  description = "Principal(Object) ID of a user/group which would receive notifications from alerts."
  type        = string
  default     = null
}

variable "notification_recipients_email_list" {
  description = "List of emails which will be notified via e-mail and/or push notifications"
  type        = list(string)
  default     = []
}
