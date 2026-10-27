variable "name_prefix" {
  description = "Prefix for resource Name tags"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone for all subnets"
  type        = string
}

variable "subnets" {
  description = "Subnets by name: CIDR block and whether the subnet is public"
  type = map(object({
    cidr   = string
    public = bool
  }))
}

variable "enable_nat_gateway" {
  description = "Create the NAT gateway. Set false between sessions to save cost; private hosts lose internet access while it is off."
  type        = bool
  default     = true
}