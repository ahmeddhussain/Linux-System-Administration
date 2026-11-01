terraform {
  # Write-only arguments (value_wo) need Terraform 1.11 or newer.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Ephemeral random_password needs random 3.7 or newer.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Same bucket as the lab layer, separate state. lab.sh down never touches it.
  backend "s3" {
    bucket       = "ahmed-statefile"
    key          = "ahmed-infra/persistent.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
