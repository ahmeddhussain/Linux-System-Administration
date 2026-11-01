# Resources that must survive `lab.sh down`. Destroying anything here breaks
# every rebuild that depends on it, so each resource has prevent_destroy.

# Ansible Vault password. Generated ephemerally and sent to SSM through a
# write-only argument, so it never appears in plan output or in state.
# control01 reads it at run time through its instance role.
ephemeral "random_password" "ansible_vault" {
  length  = 64
  special = false # 64 alphanumeric characters is about 380 bits; avoids quoting issues
}

resource "aws_ssm_parameter" "ansible_vault_password" {
  name        = "/ahmed-infra/ansible-vault-password"
  description = "Ansible Vault password, read by control01"
  type        = "SecureString" # encrypted with the AWS managed key aws/ssm

  value_wo         = ephemeral.random_password.ansible_vault.result
  value_wo_version = var.vault_password_version

  lifecycle {
    prevent_destroy = true
  }
}
