variable "aws_region" {
  description = "AWS region of the state bucket"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name (null uses the default credential chain)"
  type        = string
  default     = null
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket holding every layer's Terraform state"
  type        = string
  default     = "ahmed-statefile"
}

variable "noncurrent_version_days" {
  description = "Days to keep old state versions before they expire"
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_days >= 30
    error_message = "Keep old state versions for at least 30 days so a bad apply can be rolled back."
  }
}
