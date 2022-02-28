/*
 * variables.tf
 * Common variables to use in various Terraform files (*.tf)
 */

# The AWS region to use for the dev environment's infrastructure
variable "region" {
  default = "us-east-1"
}

# main aws account where ACM cert is provisioned
variable "aws_key" {}

variable "aws_secret" {}

variable "project_name" {}

variable "environment" {}

variable "tags" {
  default = { deployed_by = "digger" }
}