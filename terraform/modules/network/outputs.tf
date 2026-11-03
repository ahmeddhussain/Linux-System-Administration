output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "subnet_ids" {
  description = "Subnet IDs by name, available only once the fixed-IP reservations exist"
  value       = { for name, s in aws_subnet.this : name => s.id }

  # Everything placed in a subnet (instances, the endpoint) waits for the
  # reservations, so nothing can take a host's address first (D-062).
  depends_on = [aws_ec2_subnet_cidr_reservation.static]
}

output "private_route_table_id" {
  description = "ID of the route table used by private subnets"
  value       = aws_route_table.private.id
}

output "nat_public_ip" {
  description = "Public IP of the NAT gateway (null when disabled)"
  value       = try(aws_eip.nat[0].public_ip, null)
}