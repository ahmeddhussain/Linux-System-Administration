# Unit tests: mocked AWS provider, plan only, nothing is created.
#   terraform -chdir=terraform/modules/security-groups init -backend=false
#   terraform -chdir=terraform/modules/security-groups test

mock_provider "aws" {}

variables {
  name_prefix = "test"
  vpc_id      = "vpc-0123456789abcdef0"
  roles       = ["control", "workstation"]
  flows = {
    control_to_workstation = {
      from        = "control"
      to          = "workstation"
      protocol    = "tcp"
      port        = 22
      description = "SSH"
    }
  }
  cidr_ingress = {
    workstation_icmp_in = {
      role        = "workstation"
      cidr        = "10.0.0.0/16"
      protocol    = "icmp"
      port        = -1
      description = "ICMP"
    }
  }
  cidr_egress = {}
}

run "one_group_per_role" {
  command = plan

  assert {
    condition     = length(aws_security_group.role) == 2
    error_message = "Expected exactly one security group per role."
  }
}

run "each_flow_opens_both_halves_and_nothing_else" {
  command = plan

  assert {
    condition = (
      length(aws_vpc_security_group_egress_rule.flow) == 1 &&
      length(aws_vpc_security_group_ingress_rule.flow) == 1
    )
    error_message = "A flow must create exactly one egress and one ingress rule."
  }

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.flow["control_to_workstation"].from_port == 22 &&
      aws_vpc_security_group_ingress_rule.flow["control_to_workstation"].to_port == 22
    )
    error_message = "A flow must open only its own port."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.cidr) == 0
    error_message = "No CIDR egress was requested, so none may exist (default deny)."
  }
}

run "rejects_flow_to_unknown_role" {
  command = plan

  variables {
    flows = {
      bad = {
        from        = "control"
        to          = "database"
        protocol    = "tcp"
        port        = 5432
        description = "role does not exist"
      }
    }
  }

  expect_failures = [var.flows]
}

run "rejects_cidr_rule_for_unknown_role" {
  command = plan

  variables {
    cidr_egress = {
      bad = {
        role        = "database"
        cidr        = "0.0.0.0/0"
        protocol    = "tcp"
        port        = 443
        description = "role does not exist"
      }
    }
  }

  expect_failures = [var.cidr_egress]
}
