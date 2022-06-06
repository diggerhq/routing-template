

terraform {
  required_version = ">= 0.12"

  # vars are not allowed in this block
  # see: https://github.com/hashicorp/terraform/issues/22088
  backend "s3" {}

  required_providers {
    aws = {
      source  = "aws"
      version = "~> 3.0"
    }
  }
}

# The AWS Profile to use
# variable "aws_profile" {
# }

provider "aws" {
  region  = var.region
  # profile = var.aws_profile
  {% if assume_role_arn %}
  assume_role {
    role_arn={{assume_role_arn}}
    external_id={{assume_role_external_id}}
  }
  {% else %}
  access_key = var.aws_key
  secret_key = var.aws_secret
  {% endif %} 
}



