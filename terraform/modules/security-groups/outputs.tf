output "security_group_ids" {
  description = "Security group IDs by host role"
  value       = { for role, sg in aws_security_group.role : role => sg.id }
}