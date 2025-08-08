variable "admin_email" {
  type        = string
  description = "Email address for admin"
}

variable "admin_name" {
  type        = string
  description = "Email name for admin"
}

variable "app_env" {
  type        = string
  description = "Environment name, ex: 'stg' or 'prod'"
}

variable "app_name" {
  type        = string
  default     = "aps"
  description = "Used in naming ECS cluster. Recommend something like 'idp-acme'"
}

variable "app_sub_domain" {
  type    = string
  default = "app"
}

variable "auth0_client_id" {
  type = string
}
variable "auth0_client_secret" {
  type = string
}
variable "auth0_connection" {
  type    = string
  default = "Username-Password-Authentication"
}

variable "auth0_domain" {
  type = string
}

variable "aws_access_key_id" {
  type = string
}

variable "aws_account_id" {
  type        = string
  description = "AWS Account ID. Ex: 1234567890"
}

variable "aws_region" {
  description = "Region to deploy in, ex: 'us-east-1'"
  default     = "us-east-1"
}

variable "aws_secret_access_key" {
  type = string
}

variable "aws_zones" {
  type        = list(string)
  description = "A list of zones to spread instances across. Ex: [\"us-east-1c\", \"us-east-1d\", \"us-east-1e\"]"
  default     = ["us-east-1c", "us-east-1d"]
}

variable "aws_instance" {
  type        = map(string)
  description = "A map of configuration information for EC2 instances. Expected keys are 'instance_type' (e.g. \"t2.micro\"), 'volume_size' (e.g. \"8\"), and 'instance_count' (e.g. \"3\")."

  default = {
    instance_type  = "t3.small"
    volume_size    = "30"
    instance_count = "1"
  }
}

variable "buildagent_code_build_image_repo" {
  type        = string
  description = "Docker repo in ECR for Build Agent in Code Build"
  default     = "appbuilder-agent"
}

variable "buildagent_code_build_image_tag" {
  type        = string
  description = "Docker tag used for Build Agent in Code Build"
  default     = "latest"
}

variable "buildengine_api_base_url" {
  type = string
}

variable "buildengine_api_cpu" {
  type    = string
  default = "128"
}

variable "buildengine_api_memory" {
  type    = string
  default = "128"
}

variable "buildengine_cron_cpu" {
  type    = string
  default = "128"
}

variable "buildengine_cron_memory" {
  type    = string
  default = "128"
}

variable "buildengine_db_name" {
  type    = string
  default = "appbuilder"
}

variable "buildengine_db_root_user" {
  type    = string
  default = "appbuilder"
}

variable "buildengine_docker_image" {
  type    = string
  default = "ghcr.io/sillsdev/appbuilder-buildengine-api"
}

variable "buildengine_docker_tag" {
  type    = string
  default = "production"
}

variable "buildengine_subdomain" {
  type    = string
  default = "buildengine"
}

variable "cert_domain_name" {
  type        = string
  description = "Full domain name on ACM certificate"
}

variable "cloudflare_domain" {
  type    = string
  default = "scriptoria.io"
}

variable "cloudflare_email" {
  type = string
}

variable "cloudflare_token" {
  type = string
}

variable "db_storage" {
  type    = string
  default = "12"
}

variable "db_backup_retention_period" {
  type    = string
  default = "14"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_multi_az" {
  type    = string
  default = false
}

variable "ec2_ssh_key_name" {
  type    = string
  default = ""
}

variable "https_ips" {
  type        = list(string)
  description = "A list of IP address CIDR blocks for allowing https access"
}

variable "logentries_key" {
  type    = string
  default = ""
}

variable "mailer_password" {
  type = string
}

variable "mail_sender" {
  type    = string
  default = "AmazonSES"
}

variable "mailer_usefiles" {
  type = string
}

variable "mailer_username" {
  type = string
}

variable "portal_db_name" {
  type        = string
  default     = "portal"
  description = "Must begin with letter and contain only alphanumeric characters"
}

variable "portal_db_root_user" {
  type    = string
  default = "appbuilder"
}

variable "portal_cpu" {
  type    = string
  default = "128"
}

variable "portal_docker_image" {
  type    = string
  default = "appbuilder-portal-origin"
}

variable "portal_docker_tag" {
  type    = string
  default = "production"
}

variable "portal_memory" {
  type    = string
  default = "128"
}

variable "otel_cpu" {
  type    = string
  default = "128"
}

variable "otel_docker_image" {
  type    = string
  default = "otel-collector"
}

variable "otel_docker_tag" {
  type    = string
  default = "production"
}

variable "otel_memory" {
  type    = string
  default = "128"
}

variable "honeycomb_api_key" {
  type    = string
}

variable "sparkpost_api_key" {
  type    = string
  default = ""
}

variable "scripture_earth_key" {
  type = string
}

variable "ssh_ips" {
  type        = list(string)
  description = "A list of IP address CIDR blocks for allowing ssh access"
}

variable "ssh_enabled" {
  type        = string
  description = "Set to \"true\" to create security group to allow SSH access to EC2 hosts directly"
  default     = "false"
}

variable "tag_app" {
  type        = string
  description = "The AWS Tag \"app\" to be set on resources"
  default     = "scriptoria"
}

variable "tag_environment" {
  type        = string
  description = "The AWS Tag \"environment\" to be set on resources"
  default     = "production"
}

variable "tag_name" {
  type        = string
  description = "The AWS Tag \"Name\" to be set on resources"
}

variable "tag_project" {
  type        = string
  description = "The AWS Tag \"project\" to be set on resources"
  default     = "scriptoria"
}

variable "tag_scheduler" {
  type        = string
  description = "AWS Instance Scheduler name"
  default     = "none"
}

variable "tag_scheduler_running" {
  type        = string
  description = "AWS Instance Scheduler running"
  default     = "false"
}

variable "user_management_token" {
  type        = string
  description = "API Token for User Management Authentication"
}

variable "user_management_db_name" {
  type        = string
  default     = "usermgmt"
  description = "Must begin with letter and contain only alphanumeric characters"
}

variable "user_management_db_root_user" {
  type    = string
  default = "appbuilder"
}

variable "db_access_ips" {
  type        = list(string)
  description = "A list of IP address CIDR blocks for allowing db access"
}

variable "db_access_enabled" {
  type        = string
  description = "Set to \"true\" to create security group to allow db access to RDS directly"
  default     = "false"
}

variable "org_prefix" {
  type        = string
  description = "Short prefix for Organization name, letters and hyphens only. Ex: sil"
}

variable "valkey_node_type" {
  type        = string
  description = "Node type for Valkey cluster"
  default     = "cache.t3.micro"
}

variable "valkey_num_cache_nodes" {
  type        = number
  description = "Number of cache nodes for Valkey"
  default     = 1
}

variable "valkey_engine_version" {
  type        = string
  description = "Engine version for Valkey"
  default     = "7.0"
}

variable "valkey_port" {
  type        = number
  description = "Port for Valkey"
  default     = 6379
}

