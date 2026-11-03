# Unit tests: mocked AWS provider, plan only, nothing is created.
#   terraform -chdir=terraform/modules/network init -backend=false
#   terraform -chdir=terraform/modules/network test

mock_provider "aws" {}

variables {
  name_prefix       = "test"
  vpc_cidr          = "10.0.0.0/16"
  availability_zone = "us-east-1a"
  subnets = {
    public = { cidr = "10.0.0.0/24", public = true, static_cidr = "10.0.0.8/29" }
    infra  = { cidr = "10.0.1.0/24", public = false, static_cidr = "10.0.1.8/29" }
  }
}

run "nat_on_by_default" {
  command = plan

  assert {
    condition = (
      length(aws_nat_gateway.main) == 1 &&
      length(aws_eip.nat) == 1 &&
      length(aws_route.private_nat) == 1
    )
    error_message = "NAT gateway, its address and the private default route must exist when enabled."
  }
}

run "nat_off_removes_all_nat_cost" {
  command = plan

  variables {
    enable_nat_gateway = false
  }

  assert {
    condition = (
      length(aws_nat_gateway.main) == 0 &&
      length(aws_eip.nat) == 0 &&
      length(aws_route.private_nat) == 0
    )
    error_message = "With NAT disabled, no NAT gateway, EIP or route may remain."
  }
}

run "only_public_subnets_map_public_ips" {
  command = plan

  assert {
    condition = (
      aws_subnet.this["public"].map_public_ip_on_launch == true &&
      aws_subnet.this["infra"].map_public_ip_on_launch == false
    )
    error_message = "Private subnets must never give instances public addresses."
  }
}

run "every_subnet_reserves_fixed_ips" {
  command = plan

  assert {
    condition = (
      length(aws_ec2_subnet_cidr_reservation.static) == 2 &&
      alltrue([for r in aws_ec2_subnet_cidr_reservation.static : r.reservation_type == "explicit"]) &&
      aws_ec2_subnet_cidr_reservation.static["infra"].cidr_block == "10.0.1.8/29"
    )
    error_message = "Every subnet needs an explicit reservation for fixed host IPs (D-062, INC-006)."
  }
}
