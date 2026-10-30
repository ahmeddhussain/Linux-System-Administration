#!/usr/bin/env bash
# ahmed-infra lab control.
#
# Usage:
#   scripts/lab.sh up [-y]          build everything, configure it, test it, refresh the VPN client
#   scripts/lab.sh resume           redo configuration and tests on existing infrastructure
#   scripts/lab.sh verify [--full]  run the tests (--full adds the slow idempotency run)
#   scripts/lab.sh status           show the instances
#   scripts/lab.sh down [-y]        disconnect the VPN and destroy everything
#
# Environment: AWS_PROFILE, AWS_REGION, LAB_SSH_KEY (default ~/.ssh/ivolve.pem)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/infra.sh
source "$SCRIPT_DIR/lib/infra.sh"
# shellcheck source=lib/control01.sh
source "$SCRIPT_DIR/lib/control01.sh"
# shellcheck source=lib/configure.sh
source "$SCRIPT_DIR/lib/configure.sh"

AUTO_APPROVE=""
FULL=""

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

cmd_resume() {
  require_tools terraform aws ssh ssh-add
  [ -f "$KEY" ] || die "Missing key: $KEY (set LAB_SSH_KEY if yours has another name)"
  load_agent_key
  write_ssh_config
  wait_for_control01
  setup_control01
  configure_hosts
  reboot_control01_if_needed
  run_tests || warn "Some checks failed; see the FAIL lines above."
  "$SCRIPT_DIR/vpn-client.sh" refresh || warn "VPN client not refreshed; run scripts/vpn-client.sh refresh"
  log "Ready. Connect with: scripts/vpn-client.sh connect"
}

cmd_up() {
  require_tools terraform aws
  infra_apply
  cmd_resume
}

cmd_down() {
  "$SCRIPT_DIR/vpn-client.sh" disconnect > /dev/null 2>&1 || true
  infra_destroy
}

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
for arg in "$@"; do
  case "$arg" in
    -y) AUTO_APPROVE=1 ;;
    --full) FULL=1 ;;
  esac
done

case "$cmd" in
  up) cmd_up ;;
  resume) cmd_resume ;;
  verify) run_tests ;;
  status) infra_status ;;
  down) cmd_down ;;
  *) usage ;;
esac