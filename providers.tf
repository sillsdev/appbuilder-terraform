provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
  version    = "~> 2.61"
}

provider "cloudflare" {
  email   = var.cloudflare_email
  token   = var.cloudflare_token
  version = "~> 1.0"
}

