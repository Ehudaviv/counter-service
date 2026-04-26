terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket         = "ehud-counter-service-tfstate"
    key            = "infra/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "ehud-counter-service-tfstate-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "ehud-counter-service"
      ManagedBy   = "Terraform"
      Environment = "Production"
    }
  }
}