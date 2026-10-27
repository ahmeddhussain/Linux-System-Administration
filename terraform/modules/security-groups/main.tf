# One security group per role. No rules by default: everything is denied
# until a flow, cidr_ingress, or cidr_egress entry opens it.
resource "aws_security_group" "role" {
  for_each = var.roles

  name        = "${var.name_prefix}-${each.key}-sg"
  description = "${each.key}: default deny, rules added per approved flow"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-${each.key}-sg"
  }
}

# Strip every rule from the VPC's built-in default security group.
resource "aws_default_security_group" "default" {
  vpc_id = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-default-sg-unused"
  }
}

# --- Role to role flows: both halves of each connection ---------------------

resource "aws_vpc_security_group_egress_rule" "flow" {
  for_each = var.flows

  security_group_id            = aws_security_group.role[each.value.from].id
  referenced_security_group_id = aws_security_group.role[each.value.to].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
}

resource "aws_vpc_security_group_ingress_rule" "flow" {
  for_each = var.flows

  security_group_id            = aws_security_group.role[each.value.to].id
  referenced_security_group_id = aws_security_group.role[each.value.from].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
}

# --- Rules involving IP ranges ----------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = var.cidr_ingress

  security_group_id = aws_security_group.role[each.value.role].id
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
}

resource "aws_vpc_security_group_egress_rule" "cidr" {
  for_each = var.cidr_egress

  security_group_id = aws_security_group.role[each.value.role].id
  cidr_ipv4         = each.value.cidr
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
}