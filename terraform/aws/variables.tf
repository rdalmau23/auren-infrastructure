variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-1" # Ireland, typically good for Europe
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "auren"
}

variable "environment" {
  description = "Deployment environment (e.g., preprod, prod)"
  type        = string
  default     = "preprod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_password" {
  description = "Password for the RDS PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "keycloak_admin_password" {
  description = "Password for Keycloak admin user"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "El usuario u organización de GitHub (ej. rdalmau)"
  type        = string
  default     = "rdalmau"
}
