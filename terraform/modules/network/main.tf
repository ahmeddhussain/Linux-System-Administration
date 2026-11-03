locals {
  public_subnets = { for name, s in var.subnets : name => s if s.public }

  # The NAT gateway lives in the first public subnet (alphabetically).
  nat_subnet_key = sort(keys(local.public_subnets))[0]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = each.value.public

  tags = {
    Name = "${var.name_prefix}-${each.key}-subnet"
    Tier = each.key
  }
}

# Hosts have fixed private IPs. AWS gives managed interfaces (NAT gateway,
# Instance Connect Endpoint) any free address, so without this a host's IP
# can be taken before the host exists (INC-006). An explicit reservation is
# never auto-assigned; instances may still ask for an address inside it.
resource "aws_ec2_subnet_cidr_reservation" "static" {
  for_each = var.subnets

  subnet_id        = aws_subnet.this[each.key].id
  cidr_block       = each.value.static_cidr
  reservation_type = "explicit"
  description      = "Fixed host IPs (D-062)"
}

# --- NAT gateway (outbound internet for private subnets) ------------------

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.this[local.nat_subnet_key].id

  tags = {
    Name = "${var.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.main, aws_ec2_subnet_cidr_reservation.static]
}

# --- Routing --------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

resource "aws_route_table_association" "this" {
  for_each = aws_subnet.this

  subnet_id      = each.value.id
  route_table_id = var.subnets[each.key].public ? aws_route_table.public.id : aws_route_table.private.id
}