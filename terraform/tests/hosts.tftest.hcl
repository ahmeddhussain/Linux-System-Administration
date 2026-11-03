# Root-level tests of the host inventory validations: mocked AWS provider,
# plan only, no credentials or state needed. Run from terraform/:
#   terraform test

mock_provider "aws" {
  # Mocked values are random strings by default; these must look real
  # because the provider validates them during plan.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }
}

variables {
  ssh_public_key_path = "tests/fixtures/test.pub"
}

run "default_inventory_plans" {
  command = plan

  assert {
    condition     = length(output.hosts) == 6
    error_message = "The default inventory must define six hosts."
  }
}

run "rejects_unknown_subnet" {
  command = plan

  variables {
    hosts = {
      bad01 = {
        role          = "util"
        subnet        = "dmz"
        private_ip    = "10.0.1.13"
        instance_type = "t3.small"
        team          = "platform"
      }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_unknown_role" {
  command = plan

  variables {
    hosts = {
      bad01 = {
        role          = "database"
        subnet        = "infra"
        private_ip    = "10.0.1.13"
        instance_type = "t3.small"
        team          = "platform"
      }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_duplicate_private_ip" {
  command = plan

  variables {
    hosts = {
      one01 = {
        role          = "util"
        subnet        = "infra"
        private_ip    = "10.0.1.13"
        instance_type = "t3.small"
        team          = "platform"
      }
      two01 = {
        role          = "util"
        subnet        = "infra"
        private_ip    = "10.0.1.13"
        instance_type = "t3.small"
        team          = "platform"
      }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_two_control_nodes" {
  command = plan

  variables {
    hosts = {
      one01 = {
        role              = "control"
        subnet            = "infra"
        private_ip        = "10.0.1.13"
        instance_type     = "t3.small"
        team              = "platform"
        control_node_role = true
      }
      two01 = {
        role              = "control"
        subnet            = "infra"
        private_ip        = "10.0.1.14"
        instance_type     = "t3.small"
        team              = "platform"
        control_node_role = true
      }
    }
  }

  expect_failures = [var.hosts]
}

run "rejects_ip_outside_static_range" {
  command = plan

  variables {
    hosts = {
      bad01 = {
        role          = "util"
        subnet        = "infra"
        private_ip    = "10.0.1.50"
        instance_type = "t3.small"
        team          = "platform"
      }
    }
  }

  expect_failures = [var.hosts]
}
