# shellcheck shell=bash
# Terraform: build, destroy, and inspect the lab infrastructure.

infra_apply() {
  [ -f "$TF_DIR/terraform.tfvars" ] || die "Missing terraform/terraform.tfvars"
  log "Terraform: init and apply"
  terraform -chdir="$TF_DIR" init -input=false > /dev/null
  terraform -chdir="$TF_DIR" apply ${AUTO_APPROVE:+-auto-approve}
}

infra_destroy() {
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