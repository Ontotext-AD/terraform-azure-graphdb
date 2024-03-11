# Common configurations

variable "resource_name_prefix" {
  description = "Resource name prefix used for tagging and naming Azure resources"
  type        = string
}

variable "location" {
  description = "Azure geographical location where resources will be deployed"
  type        = string
}

variable "zones" {
  description = "Availability zones"
  type        = list(number)
  default     = [1, 2, 3]
}

variable "resource_group_id" {
  description = "Identifier of the resource group where GraphDB will be deployed."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where GraphDB will be deployed."
  type        = string
}

# Networking

variable "virtual_network_id" {
  description = "Virtual network the DNS will be linked to"
  type        = string
}

variable "graphdb_subnet_id" {
  description = "Identifier of the subnet where GraphDB will be deployed"
  type        = string
}

variable "graphdb_inbound_address_prefixes" {
  description = "Source address prefixes allowed for inbound traffic to GraphDB"
  type        = list(string)
}

variable "graphdb_ssh_inbound_address_prefixes" {
  description = "Source address prefixes allowed for inbound SSH traffic to GraphDB's VMs"
  type        = list(string)
}

variable "graphdb_outbound_address_prefix" {
  description = "Destination address prefix allowed for outbound traffic from GraphDB"
  type        = string
  default     = "Internet"
}

variable "graphdb_outbound_address_prefixes" {
  description = "Destination address prefixes allowed for outbound traffic from GraphDB"
  type        = list(string)
  default     = []
}

# Application Gateway

variable "application_gateway_backend_address_pool_ids" {
  description = "Array of identifiers of load balancer backend pools for the GraphDB nodes"
  type        = list(string)
  default     = []
}

# App Configuration

variable "app_configuration_id" {
  description = "Identifier of the App Configuration store for GraphDB"
  type        = string
}

variable "app_configuration_endpoint" {
  description = "Endpoint of the App Configuration store for GraphDB"
  type        = string
}

# Backups storage

variable "backup_storage_account_name" {
  description = "Storage account name for storing GraphDB backups"
  type        = string
}

variable "backup_storage_container_id" {
  description = "Identifier of the storage container for GraphDB backups"
  type        = string
}

variable "backup_storage_container_name" {
  description = "Name of the storage container for GraphDB backups"
  type        = string
}

variable "backup_schedule" {
  description = "Cron expression for the backup job."
  type        = string
}

# GraphDB configurations

variable "graphdb_external_address_fqdn" {
  description = "Public FQDN where GraphDB can be addressed"
  type        = string
}

variable "graphdb_license_path" {
  description = "Local path to a file, containing a GraphDB Enterprise license."
  type        = string
}

variable "graphdb_license_secret_name" {
  description = "Name of the configuration in App Configuration that contains the GraphDB license."
  type        = string
  default     = "graphdb-license"
}

variable "graphdb_cluster_token" {
  description = "Secret token used to secure the internal GraphDB cluster communication."
  type        = string
  default     = null
  sensitive   = true
}

variable "graphdb_cluster_token_name" {
  description = "Name of the configuration in App Configuration that contains the GraphDB cluster secret token."
  type        = string
  default     = "graphdb-cluster-token"
}

variable "graphdb_password" {
  description = "Administrator credentials for accessing GraphDB"
  type        = string
  default     = null
  sensitive   = true
}

variable "graphdb_password_secret_name" {
  description = "Name of the configuration in App Configuration that contains the GraphDB administrator credentials"
  type        = string
  default     = "graphdb-password"
}

variable "graphdb_properties_path" {
  description = "Path to a local file containing GraphDB properties (graphdb.properties) that would be appended to the default in the VM."
  type        = string
  default     = null
}

variable "graphdb_properties_secret_name" {
  description = "Name of the configuration in App Configuration that contains the GraphDB properties."
  type        = string
  default     = "graphdb-properties"
}

variable "graphdb_java_options" {
  description = "GraphDB options to pass to GraphDB with GRAPHDB_JAVA_OPTS environment variable."
  type        = string
  default     = null
}

variable "graphdb_java_options_secret_name" {
  description = "Name of the configuration in App Configuration that contains the GraphDB GRAPHDB_JAVA_OPTS configurations."
  type        = string
  default     = "graphdb-java-options"
}

# GraphDB VM image configuration

variable "graphdb_version" {
  description = "GraphDB version from the marketplace offer"
  type        = string
}

variable "graphdb_sku" {
  description = "GraphDB SKU from the marketplace offer"
  type        = string
}

variable "graphdb_image_id" {
  description = "GraphDB image ID to use for the scale set VM instances in place of the default marketplace offer"
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

variable "encryption_at_host" {
  description = "Enables encryption at rest on the VM host"
  type        = bool
  default     = true
}

# Managed disks

variable "disk_storage_account_type" {
  description = "Storage account type for the data disks"
  type        = string
}

variable "disk_size_gb" {
  description = "Size of the managed data disk which will be created"
  type        = number
}

variable "disk_iops_read_write" {
  description = "Data disk IOPS"
  type        = number
}

variable "disk_mbps_read_write" {
  description = "Data disk throughput"
  type        = number
}

variable "disk_network_access_policy" {
  description = "Network access policy for the managed disks"
  type        = string
}

variable "disk_public_network_access" {
  description = "Public network access enabled for the managed disks"
  type        = bool
}

# Application Insights

variable "appi_connection_string" {
  description = "Connection string for Application Insights"
  type        = string
}

variable "appi_sampling_percentage" {
  description = "Sampling percentage for Application Insights"
  type        = number
  default     = 100
}

variable "appi_logging_level" {
  description = "Logging level configuration for the Application Insights"
  type        = string
  default     = "WARN"
}

variable "appi_dependency_sampling_override" {
  description = "Override value for Application Insights dependency sampling percentage"
  type        = number
  default     = 0
}

variable "appi_grpc_sampling_override" {
  description = "Override value for Application Insights grpc communication sampling percentage"
  type        = number
  default     = 0
}

variable "appi_repositories_requests_sampling" {
  description = "Override value for GraphDB requests to /repositories sampling percentage"
  type        = number
  default     = 50
}

variable "scaleset_actions_recipients_email_list" {
  description = "List of emails which will be notified for any scaling changes in the VMSS"
  type        = list(string)
}

# Public IP configurations

variable "nat_gateway_pip_idle_timeout" {
  description = "Specifies the timeout for the TCP idle connection"
  type        = number
  default     = 5
}
