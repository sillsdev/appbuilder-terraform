variable "admin_email" {
  type        = "string"
  description = "Email address for admin"
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

variable "api_cpu" {
  type    = "string"
  default = "128"
}

variable "api_memory" {
  type    = "string"
  default = "128"
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
    instance_type  = "t2.medium"
    volume_size    = "30"
    instance_count = "1"
  }
}

variable "buildengine_docker_image" {
  type    = "string"
  default = "sillsdev/appbuilder-buildengine-api"
}

variable "buildengine_docker_tag" {
  type    = "string"
  default = "production"
}

variable "buildengine_git_user_email" {
  type    = "string"
  default = "appbuilder@buildagent.com"
}

variable "buildengine_git_user_name" {
  type    = "string"
  default = "AppBuilder Build Agent"
}

variable "buildengine_repo_branch" {
  type    = "string"
  default = "master"
}

variable "buildengine_subdomain" {
  type    = "string"
  default = "buildengine"
}

variable "cert_domain_name" {
  type        = "string"
  description = "Full domain name on ACM certificate"
}

variable "cron_cpu" {
  type    = "string"
  default = "128"
}

variable "cron_memory" {
  type    = "string"
  default = "128"
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

variable "db_name" {
  type    = "string"
  default = "appbuilder"
}

variable "db_root_user" {
  type    = "string"
  default = "appbuilder"
}

variable "domain" {
  type        = "string"
  description = "Top level domain for URLs, ex: sil.org"
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

variable "mailer_usefiles" {
  type = "string"
}

variable "mailer_username" {
  type = "string"
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
