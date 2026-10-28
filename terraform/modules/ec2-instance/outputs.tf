output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address"
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Elastic IP address (null if the host has none)"
  value       = try(aws_eip.this[0].public_ip, null)
}

output "primary_network_interface_id" {
  description = "ID of the instance's primary network interface"
  value       = aws_instance.this.primary_network_interface_id
}