# Renamed 2026-11-01: the role also reads secrets now, so "ansible_inventory"
# no longer described it. These blocks keep the state addresses; the AWS
# names change too (see iam.tf), which replaces the role and profile once.
moved {
  from = aws_iam_role.ansible_inventory
  to   = aws_iam_role.control_node
}

moved {
  from = aws_iam_role_policy.ansible_inventory
  to   = aws_iam_role_policy.describe_instances
}

moved {
  from = aws_iam_instance_profile.ansible_inventory
  to   = aws_iam_instance_profile.control_node
}
