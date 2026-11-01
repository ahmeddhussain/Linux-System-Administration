# Instance role for the control node (control01; control_node_role in the
# hosts variable): discover hosts for the Ansible dynamic inventory and read
# the project's secrets from SSM. No access keys are stored on the server.

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

resource "aws_iam_role" "control_node" {
  name               = "${var.company_name}-control-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  # On a rename, build the new role before removing the old one so control01
  # is never left without credentials.
  lifecycle {
    create_before_destroy = true
  }
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

resource "aws_iam_role_policy" "describe_instances" {
  name   = "describe-instances"
  role   = aws_iam_role.control_node.id
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
  role   = aws_iam_role.control_node.id
  policy = data.aws_iam_policy_document.read_secrets.json
}

resource "aws_iam_instance_profile" "control_node" {
  name = "${var.company_name}-control-node"
  role = aws_iam_role.control_node.name

  lifecycle {
    create_before_destroy = true
  }
}
