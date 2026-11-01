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

  # On a rename, build the new role (and its policies and profile, below)
  # before removing the old one so control01 never loses its permissions.
  # The inline policies need it too: without it they were deleted first and
  # the old role had no permissions for a few seconds (2026-11-01 rename).
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

  lifecycle {
    create_before_destroy = true
  }
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

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "control_node" {
  name = "${var.company_name}-control-node"
  role = aws_iam_role.control_node.name

  lifecycle {
    create_before_destroy = true
  }
}

# Instance role for util01 (backup_writer in the hosts variable): read and
# write its backups in the bucket from terraform/persistent (D-056). No
# delete permission: with versioning on, an overwrite keeps the old copy,
# so a compromised util01 cannot erase the backup history.
locals {
  backup_bucket_arn = "arn:aws:s3:::ahmed-infra-backups-${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_role" "backup_writer" {
  name               = "${var.company_name}-backup-writer"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "backup_writer" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [local.backup_bucket_arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
    resources = ["${local.backup_bucket_arn}/util01/*"]
  }
}

resource "aws_iam_role_policy" "backup_writer" {
  name   = "util01-backups"
  role   = aws_iam_role.backup_writer.id
  policy = data.aws_iam_policy_document.backup_writer.json
}

resource "aws_iam_instance_profile" "backup_writer" {
  name = "${var.company_name}-backup-writer"
  role = aws_iam_role.backup_writer.name
}
