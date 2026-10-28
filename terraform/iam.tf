# Read-only role so control01 can discover hosts for the Ansible dynamic
# inventory. No access keys are stored on the server.

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
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"] # Describe actions do not support resource-level limits
  }
}

resource "aws_iam_role_policy" "ansible_inventory" {
  name   = "describe-instances"
  role   = aws_iam_role.ansible_inventory.id
  policy = data.aws_iam_policy_document.describe_instances.json
}

resource "aws_iam_instance_profile" "ansible_inventory" {
  name = "${var.company_name}-ansible-inventory"
  role = aws_iam_role.ansible_inventory.name
}