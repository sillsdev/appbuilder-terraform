terraform {
  required_version = ">= 0.15"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.67"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.33.1"
    }
    random = {
      source = "hashicorp/random"
    }
    template = {
      source = "hashicorp/template"
    }
  }
}
