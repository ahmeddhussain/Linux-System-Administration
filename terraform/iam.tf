# Instance role for control01: discover hosts for the Ansible dynamic
# inventory and read the project's secrets from SSM. No access keys are
# stored on the server.

data "aws_caller_identity" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ansible_inventory" {
  name               = "${var.company_name}-ansible-inventory"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "describe_instances" {
  statement {
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeRegions",
    ]
    resources = ["*"] # Describe actions do not support resource-level limits
  }
}

resource "aws_iam_role_policy" "ansible_inventory" {
  name   = "describe-instances"
  role   = aws_iam_role.ansible_inventory.id
  policy = data.aws_iam_policy_document.describe_instances.json
}

# Secrets live under /ahmed-infra/ in SSM (created by terraform/persistent).
# Read only; the parameters use the AWS managed key aws/ssm, so decrypt is
# allowed only when SSM makes the call on control01's behalf.
data "aws_iam_policy_document" "read_secrets" {
  statement {
    actions = ["ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/ahmed-infra/*",
    ]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.ansible_inventory.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

resource "aws_iam_instance_profile" "ansible_inventory" {
  name = "${var.company_name}-ansible-inventory"
  role = aws_iam_role.ansible_inventory.name
}
