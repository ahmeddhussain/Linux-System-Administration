# shellcheck shell=bash
# Terraform: build, destroy, and inspect the lab infrastructure.

infra_apply() {
  [ -f "$TF_DIR/terraform.tfvars" ] || die "Missing terraform/terraform.tfvars"
  log "Terraform: init and apply"
  terraform -chdir="$TF_DIR" init -input=false > /dev/null
  terraform -chdir="$TF_DIR" apply ${AUTO_APPROVE:+-auto-approve}
}

infra_destroy() {
  if [ -z "${AUTO_APPROVE:-}" ]; then
    read -r -p "Destroy ALL lab infrastructure? Type 'destroy' to continue: " answer
    [ "$answer" = "destroy" ] || die "Cancelled."
  fi
  log "Terraform: destroy"
  terraform -chdir="$TF_DIR" destroy -auto-approve
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