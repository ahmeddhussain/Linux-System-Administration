output "vault_password_parameter_name" {
  description = "SSM parameter holding the Ansible Vault password"
  value       = aws_ssm_parameter.ansible_vault_password.name
}

output "vault_password_parameter_arn" {
  description = "ARN of the Vault password parameter, for IAM policies"
  value       = aws_ssm_parameter.ansible_vault_password.arn
}

output "backup_bucket_name" {
  description = "S3 bucket holding util01's backups"
  value       = aws_s3_bucket.backups.id
}
