# shellcheck shell=bash
# Shared settings and helpers. Sourced by the scripts in scripts/.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$ROOT/terraform"
REGION="${AWS_REGION:-us-east-1}"
KEY="${LAB_SSH_KEY:-$HOME/.ssh/ivolve.pem}"
SSH_INCLUDE="$HOME/.ssh/ahmed-lab.conf"
REMOTE_ANSIBLE='source ~/ansible-venv/bin/activate && cd ~/ahmed-infra/ansible'

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" > /dev/null || die "Missing tool: $tool"
  done
}

tf_output() {
  terraform -chdir="$TF_DIR" output -raw "$1"
}

# Instance ID of a running lab host, by its Name tag.
instance_id() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$1" "Name=tag:Project,Values=ahmed-infra" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text
}