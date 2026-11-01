terraform {
  required_version = "~> 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # The bucket holds its own state. If the bucket is ever gone, comment this
  # block out, apply with local state, then `terraform init -migrate-state`.
  backend "s3" {
    bucket       = "ahmed-statefile"
    key          = "ahmed-infra/bootstrap.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
