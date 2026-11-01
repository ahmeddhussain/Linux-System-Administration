# shellcheck shell=bash
# Terraform: build, destroy, and inspect the lab infrastructure.

infra_apply() {
  [ -f "$TF_DIR/terraform.tfvars" ] || die "Missing terraform/terraform.tfvars"
  log "Terraform: init and apply"
  terraform -chdir="$TF_DIR" init -input=false > /dev/null
  terraform -chdir="$TF_DIR" apply ${AUTO_APPROVE:+-auto-approve}
}

infra_destroy() {
  # util01's data volume is destroyed with the lab: back it up first (D-056).
  # Refuse to destroy without a backup unless the operator agrees.
  log "Backing up util01 data to S3"
  if ! ssh control01 "$REMOTE_ANSIBLE && ansible util01 -b -m command -a '/usr/local/sbin/ahmed-backup backup'" < /dev/null; then
    warn "util01 backup failed; its data will be lost by the destroy."
    if [ -z "${AUTO_APPROVE:-}" ]; then
      read -r -p "Destroy anyway? Type 'yes' to continue: " answer
      [ "$answer" = "yes" ] || die "Cancelled."
    fi
  fi

  # Lab layer only: terraform/persistent and terraform/bootstrap have their
  # own state and are never touched here. Without -y, Terraform lists every
  # resource it will delete and asks for "yes" before deleting anything.
  log "Terraform: destroy (lab layer)"
  terraform -chdir="$TF_DIR" destroy ${AUTO_APPROVE:+-auto-approve}
  rm -f "$SSH_INCLUDE"
  echo "Done. The state bucket, Git repo, and your keys are untouched."
}

infra_status() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Project,Values=ahmed-infra" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name,InstanceType,PrivateIpAddress]' \
    --output table
}