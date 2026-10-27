data "aws_ami" "os" {
  most_recent = true
  owners      = [var.ami_owner_id]

  filter {
    name   = "name"
    values = [var.ami_name_pattern]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# The public half of your existing ivolve key. The private key never leaves
# your laptop and never enters Terraform.
resource "aws_key_pair" "bootstrap" {
  key_name   = "${var.company_name}-bootstrap"
  public_key = file(pathexpand(var.ssh_public_key_path))
}