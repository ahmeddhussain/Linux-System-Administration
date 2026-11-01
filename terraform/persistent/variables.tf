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

variable "vault_password_version" {
  description = "Bump to generate and store a new Ansible Vault password. Rekey every vault file first, or they become unreadable."
  type        = number
  default     = 1
}

variable "backup_noncurrent_days" {
  description = "Days to keep older backup versions of util01's data"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_noncurrent_days >= 7
    error_message = "Keep older backups for at least 7 days."
  }
}
