variable "admin_email" {
  type        = "string"
  description = "Email address for admin"
}

variable "admin_name" {
  type        = "string"
  description = "Email name for admin"
}

variable "api_port" {
  type    = "string"
  default = "7081"
}

variable "api_url" {
  type        = "string"
  default     = "http://api:7081"
  description = "URL used by UI to proxy api calls from frontend JS; port must match api_port"
}

variable "app_env" {
  type        = "string"
  description = "Environment name, ex: 'stg' or 'prod'"
}

variable "app_name" {
  type        = "string"
  default     = "aps"
  description = "Used in naming ECS cluster. Recommend something like 'idp-acme'"
}

variable "app_sub_domain" {
  type    = "string"
  default = "app"
}

variable "auth0_audience" {
  type    = "string"
  default = "n8IAE2O17FBrlQ667x5mydhpqelCBUWG"
}

variable "auth0_client_id" {
  type = "string"
}

variable "auth0_domain" {
  type    = "string"
  default = "https://sil-appbuilder.auth0.com"
}

variable "auth0_token_access_client_id" {
  type = "string"
}

variable "auth0_token_access_client_secret" {
  type = "string"
}

variable "aws_access_key_id" {
  type = "string"
}

variable "aws_account_id" {
  type        = "string"
  description = "AWS Account ID. Ex: 1234567890"
}

variable "aws_region" {
  description = "Region to deploy in, ex: 'us-east-1'"
  default     = "us-east-1"
}

variable "aws_secret_access_key" {
  type = "string"
}

variable "aws_zones" {
  type        = "list"
  description = "A list of zones to spread instances across. Ex: [\"us-east-1c\", \"us-east-1d\", \"us-east-1e\"]"
  default     = ["us-east-1c", "us-east-1d"]
}

variable "aws_instance" {
  type        = "map"
  description = "A map of configuration information for EC2 instances. Expected keys are 'instance_type' (e.g. \"t2.micro\"), 'volume_size' (e.g. \"8\"), and 'instance_count' (e.g. \"3\")."

  default = {
    instance_type  = "t3.small"
    volume_size    = "8"
    instance_count = "1"
  }
}

variable "bugsnag_apikey" {
  type = "string"
}

variable "buildagent_code_build_image_tag" {
  type        = "string"
  description = "Docker tag used for Build Agent in Code Build"
  default     = "production"
}

variable "buildengine_api_base_url" {
  type = "string"
}

variable "buildengine_api_cpu" {
  type    = "string"
  default = "128"
}

variable "buildengine_api_memory" {
  type    = "string"
  default = "128"
}

variable "buildengine_cron_cpu" {
  type    = "string"
  default = "128"
}

variable "buildengine_cron_memory" {
  type    = "string"
  default = "128"
}

variable "buildengine_db_name" {
  type    = "string"
  default = "appbuilder"
}

variable "buildengine_db_root_user" {
  type    = "string"
  default = "appbuilder"
}

variable "buildengine_docker_image" {
  type    = "string"
  default = "sillsdev/appbuilder-buildengine-api"
}

variable "buildengine_docker_tag" {
  type    = "string"
  default = "production"
}

variable "buildengine_subdomain" {
  type    = "string"
  default = "buildengine"
}

variable "cert_domain_name" {
  type        = "string"
  description = "Full domain name on ACM certificate"
}

variable "cloudflare_domain" {
  type    = "string"
  default = "scriptoria.io"
}

variable "cloudflare_email" {
  type = "string"
}

variable "cloudflare_token" {
  type = "string"
}

variable "db_storage" {
  type    = "string"
  default = "8"
}

variable "db_backup_retention_period" {
  type    = "string"
  default = "14"
}

variable "db_multi_az" {
  type    = "string"
  default = false
}

variable "db_bootstrap" {
  type    = "string"
  default = "0"
}

variable "db_bootstrap_file" {
  type    = "string"
  default = ""
}

variable "db_sampledata" {
  type    = "string"
  default = "0"
}

variable "db_sampledata_buildengine_api_access_token" {
  type    = "string"
  default = ""
}

variable "ec2_ssh_key_name" {
  type    = "string"
  default = ""
}

variable "https_ips" {
  type        = "list"
  description = "A list of IP address CIDR blocks for allowing https access"
}

variable "logentries_key" {
  type    = "string"
  default = ""
}

variable "mailer_password" {
  type = "string"
}

variable "mail_sender" {
  type    = "string"
  default = "SparkPost"
}

variable "mail_sparkpost_apikey" {
  type = "string"
}

variable "mailer_usefiles" {
  type = "string"
}

variable "mailer_username" {
  type = "string"
}

variable "portal_db_name" {
  type        = "string"
  default     = "portal"
  description = "Must begin with letter and contain only alphanumeric characters"
}

variable "portal_db_root_user" {
  type    = "string"
  default = "appbuilder"
}

variable "portal_api_cpu" {
  type    = "string"
  default = "128"
}

variable "portal_api_docker_image" {
  type    = "string"
  default = "appbuilder-portal-api"
}

variable "portal_api_docker_tag" {
  type    = "string"
  default = "production"
}

variable "portal_api_memory" {
  type    = "string"
  default = "128"
}

variable "portal_ui_cpu" {
  type    = "string"
  default = "128"
}

variable "portal_ui_docker_image" {
  type    = "string"
  default = "appbuilder-portal-nginx"
}

variable "portal_ui_docker_tag" {
  type    = "string"
  default = "production"
}

variable "portal_ui_memory" {
  type    = "string"
  default = "128"
}

variable "ssh_ips" {
  type        = "list"
  description = "A list of IP address CIDR blocks for allowing ssh access"
}

variable "ssh_enabled" {
  type        = "string"
  description = "Set to \"true\" to create security group to allow SSH access to EC2 hosts directly"
  default     = "false"
}

variable "db_access_ips" {
  type        = "list"
  description = "A list of IP address CIDR blocks for allowing db access"
}

variable "db_access_enabled" {
  type        = "string"
  description = "Set to \"true\" to create security group to allow db access to RDS directly"
  default     = "false"
}

variable "org_prefix" {
  type        = "string"
  description = "Short prefix for Organization name, letters and hyphens only. Ex: sil"
}
