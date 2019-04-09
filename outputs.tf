// Application load balancer outputs
output "alb_dns_name" {
  value = "${module.alb.dns_name}"
}

output "appbuilder_access_key_id" {
  value = "${aws_iam_access_key.appbuilder.id}"
}

output "appbuilder_secret_access_key" {
  value = "${aws_iam_access_key.appbuilder.secret}"
}

output "api_access_token" {
  value = "${random_id.api_access_token.hex}"
}

output "buildengine_access_key_id" {
  value = "${aws_iam_access_key.buildengine.id}"
}

output "buildengine_secret_access_key" {
  value = "${aws_iam_access_key.buildengine.secret}"
}

output "buildengine_db_address" {
  value = "${module.rds.address}"
}

output "buildengine_db_root_pass" {
  value = "${random_id.buildengine_db_root_pass.hex}"
}

output "buildengine_db_username" {
  value = "${var.buildengine_db_root_user}"
}
