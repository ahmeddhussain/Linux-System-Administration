variable "name" {
  description = "Host name (short), for example control01"
  type        = string
}

variable "domain" {
  description = "Internal DNS domain, used to build the FQDN"
  type        = string
}

variable "ami_id" {
  description = "Image ID to launch"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "subnet_id" {
  description = "Subnet the instance is placed in"
  type        = string
}

variable "private_ip" {
  description = "Fixed private IP address"
  type        = string
}

variable "security_group_ids" {
  description = "Security groups attached to the instance"
  type        = list(string)
}

variable "key_name" {
  description = "Key pair used for the default user"
  type        = string
}

variable "iam_instance_profile" {
  description = "Name of an IAM instance profile to attach (null for none)"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "allocate_eip" {
  description = "Attach an Elastic IP (only for hosts that must be reachable from the internet)"
  type        = bool
  default     = false
}

variable "source_dest_check" {
  description = "Set false only for hosts that forward traffic (VPN gateway)"
  type        = bool
  default     = true
}

variable "extra_volumes" {
  description = "Additional EBS volumes by name"
  type = map(object({
    device_name = string
    size        = number
  }))
  default = {}
}

variable "tags" {
  description = "Extra tags (for example Role and Team)"
  type        = map(string)
  default     = {}
}