#!/usr/bin/env bash
# ahmed-infra lab control: rebuild or tear down the whole company.
#
# Usage:
#   scripts/lab.sh up [-y]     build everything and configure it
#   scripts/lab.sh resume      redo the configuration on existing infrastructure
#   scripts/lab.sh verify      run the health checks
#   scripts/lab.sh status      show the instances
#   scripts/lab.sh down [-y]   destroy everything (state bucket and Git are kept)
#
# Set AWS_PROFILE and AWS_REGION in your shell if you use them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
REGION="${AWS_REGION:-us-east-1}"
KEY="$HOME/.ssh/ivolve.pem"
SSH_INCLUDE="$HOME/.ssh/ahmed-lab.conf"
REMOTE_ANSIBLE='source ~/ansible-venv/bin/activate && cd ~/ahmed-infra/ansible'
AUTO_APPROVE=""

log() { printf '\n==> %s\n' "$*"; }

usage() {
  sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

check_tools() {
  local tool
  for tool in terraform aws ssh ssh-add; do
    command -v "$tool" > /dev/null || { echo "Missing tool: $tool"; exit 1; }
  done
  [ -f "$TF_DIR/terraform.tfvars" ] || { echo "Missing terraform/terraform.tfvars (it must set admin_cidr)"; exit 1; }
  [ -f "$KEY" ] || { echo "Missing key: $KEY"; exit 1; }
}

load_agent_key() {
  # control01 borrows this key once per rebuild to create the ansible account.
  local rc=0
  ssh-add -l > /dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    echo 'No ssh-agent is running. Start one with: eval "$(ssh-agent)"  then retry.'
    exit 1
  fi
  ssh-add "$KEY"
}

write_ssh_config() {
  log "Writing the SSH entry for control01"
  local id
  id="$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=control01" "Name=tag:Project,Values=ahmed-infra" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)"
  [ -n "$id" ] || { echo "control01 is not running."; exit 1; }
  cat > "$SSH_INCLUDE" << EOF
Host control01
  HostName $id
  User ec2-user
  IdentityFile $KEY
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ProxyCommand aws ec2-instance-connect open-tunnel --instance-id %h --region $REGION
EOF
}

wait_for_control01() {
  log "Waiting for control01 (the endpoint and first boot can take several minutes)"
  local i
  for i in $(seq 1 60); do
    if ssh -o ConnectTimeout=10 -o BatchMode=yes control01 true 2> /dev/null; then
      echo "control01 is reachable."
      return 0
    fi
    sleep 15
  done
  echo "control01 was not reachable after 15 minutes."
  return 1
}

setup_control01() {
  log "Preparing control01 (packages, venv, collections, key, repo)"
  ssh control01 'bash -s' < "$ROOT/scripts/control01-setup.sh"
}

configure_hosts() {
  log "Creating the ansible account on every host (one-time key forwarding)"
  ssh -A control01 "$REMOTE_ANSIBLE && ansible-playbook playbooks/bootstrap.yml -e ansible_user=ec2-user"
  log "Applying the baseline to every host"
  ssh control01 "$REMOTE_ANSIBLE && ansible-playbook playbooks/site.yml"
}

cmd_resume() {
  check_tools
  load_agent_key
  write_ssh_config
  wait_for_control01
  setup_control01
  configure_hosts
  cmd_verify
}

cmd_up() {
  check_tools
  log "Terraform init and apply"
  terraform -chdir="$TF_DIR" init -input=false
  terraform -chdir="$TF_DIR" apply ${AUTO_APPROVE:+-auto-approve}
  cmd_resume
  log "Done. VPN endpoint (for later):"
  terraform -chdir="$TF_DIR" output vpn_endpoint
}

cmd_verify() {
  log "Health checks"
  ssh control01 "$REMOTE_ANSIBLE && ansible all -m ping && ansible all -b -m command -a getenforce && ansible all -b -m shell -a 'systemctl is-active firewalld chronyd sshd'"
  log "Idempotency check (expect changed=0 on every host)"
  ssh control01 "$REMOTE_ANSIBLE && ansible-playbook playbooks/site.yml | tail -n 12"
}

cmd_status() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Project,Values=ahmed-infra" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name,InstanceType,PrivateIpAddress]' \
    --output table
}

cmd_down() {
  command -v terraform > /dev/null || { echo "Missing tool: terraform"; exit 1; }
  if [ -z "$AUTO_APPROVE" ]; then
    read -r -p "Destroy ALL lab infrastructure? Type 'destroy' to continue: " answer
    [ "$answer" = "destroy" ] || { echo "Cancelled."; exit 1; }
  fi
  terraform -chdir="$TF_DIR" destroy -auto-approve
  echo "Done. The state bucket and your Git repo are untouched."
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
for arg in "$@"; do
  if [ "$arg" = "-y" ]; then AUTO_APPROVE=1; fi
done

case "$cmd" in
  up) cmd_up ;;
  resume) cmd_resume ;;
  verify) cmd_verify ;;
  status) cmd_status ;;
  down) cmd_down ;;
  *) usage ;;
esac