terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
