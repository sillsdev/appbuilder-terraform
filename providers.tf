provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key_id
  secret_key = var.aws_secret_access_key
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

