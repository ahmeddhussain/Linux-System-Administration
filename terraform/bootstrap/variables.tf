variable "aws_region" {
  description = "AWS region for the lab"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name (null uses the default credential chain)"
  type        = string
  default     = null
}

variable "company_name" {
  description = "Company name, used as a prefix for resource names"
  type        = string
  default     = "ahmed"
}

variable "availability_zone" {
  description = "Availability zone for the lab subnets"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  description = "CIDR block for the company VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnets" {
  description = "Subnets by tier: CIDR block and whether the subnet is public"
  type = map(object({
    cidr   = string
    public = bool
  }))
  default = {
    public      = { cidr = "10.0.0.0/24", public = true }
    infra       = { cidr = "10.0.1.0/24", public = false }
    workstation = { cidr = "10.0.2.0/24", public = false }
    app         = { cidr = "10.0.3.0/24", public = false }
  }
}

variable "enable_nat_gateway" {
  description = "Create the NAT gateway. Set false between sessions to save cost."
  type        = bool
  default     = true
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (for example 203.0.113.10/32). Only this address can reach bastion01."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR block and must not be 0.0.0.0/0."
  }
}