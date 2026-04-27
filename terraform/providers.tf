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
    # Add Helm provider
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
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

# Configure Helm to use the EKS cluster we just built
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name]
      command     = "aws"
    }
  }
}