// Application load balancer outputs
output "alb_dns_name" {
  value = module.alb.dns_name
}

output "app_ui_url" {
  value = var.deploy_portal ? "https://${cloudflare_record.app_ui[0].hostname}" : "Portal not deployed"
}

output "appbuilder_access_key_id" {
  value = aws_iam_access_key.appbuilder.id
}

output "appbuilder_secret_access_key" {
  value     = aws_iam_access_key.appbuilder.secret
  sensitive = true
}

output "api_access_token" {
  value = random_id.api_access_token.hex
}

output "buildengine_access_key_id" {
  value = aws_iam_access_key.buildengine.id
}

output "buildengine_secret_access_key" {
  value     = aws_iam_access_key.buildengine.secret
  sensitive = true
}

output "buildengine_db_address" {
  value = aws_db_instance.db_instance.address
}

output "buildengine_db_root_pass" {
  value = random_id.buildengine_db_root_pass.hex
}

output "db_admin_root_pass" {
  value = random_id.db_admin_root_pass.hex
}

output "buildengine_db_username" {
  value = var.buildengine_db_root_user
}

output "portal_db_address" {
  value = var.deploy_portal ? aws_db_instance.db_instance.address : "Portal not deployed"
}

output "portal_db_root_pass" {
  value = var.deploy_portal ? random_id.portal_db_root_pass[0].hex : "Portal not deployed"
}

output "portal_db_username" {
  value = var.deploy_portal ? var.portal_db_root_user : "Portal not deployed"
}

#output "user_management_db_address" {
#  value = module.user_management_db.address
#}
#
#output "user_management_db_root_pass" {
#  value = random_id.user_management_db_root_pass.hex
#}
#
#output "user_management_db_username" {
#  value = var.user_management_db_root_user
#}

output "portal_email_id" {
  value = var.deploy_portal ? aws_iam_access_key.portal[0].id : "Portal not deployed"
}

output "portal_email_secret" {
  value     = var.deploy_portal ? aws_iam_access_key.portal[0].secret : "Portal not deployed"
  sensitive = true
}

output "scriptoria_auth0_secret" {
  value = var.deploy_portal ? random_id.auth0_secret[0].hex : var.scriptoria_auth0_secret
}
output "scriptoria_url" {
  value = var.deploy_portal ? "https://${var.app_sub_domain}.${var.cloudflare_domain}" : var.scriptoria_url
}

output "valkey_address" {
  value = var.deploy_portal ? aws_elasticache_replication_group.valkey[0].primary_endpoint_address : "Portal not deployed"
}

