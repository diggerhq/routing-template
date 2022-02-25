

terraform {
  required_version = ">= 0.12"

  # vars are not allowed in this block
  # see: https://github.com/hashicorp/terraform/issues/22088
  backend "s3" {}

}

# The AWS Profile to use
# variable "aws_profile" {
# }

provider "aws" {
  version = "~ 3.0"
  region  = var.region
  # profile = var.aws_profile
  access_key = var.aws_key
  secret_key = var.aws_secret  
}



