# shellcheck shell=bash
# Configuring the hosts with Ansible, and verifying the result.

load_agent_key() {
  # control01 borrows this key once per rebuild to create the ansible account.
  local rc=0
  ssh-add -l > /dev/null 2>&1 || rc=$?
  [ "$rc" -ne 2 ] || die 'No ssh-agent is running. Start one with: eval "$(ssh-agent)"  then retry.'
  ssh-add "$KEY"
}

configure_hosts() {
  log "Creating the ansible account on every host (one-time key forwarding)"
  ssh -A control01 "$REMOTE_ANSIBLE && ansible-playbook playbooks/bootstrap.yml -e ansible_user=ec2-user"
  log "Patching and configuring every host (site.yml; the first run takes a while)"
  ssh control01 "$REMOTE_ANSIBLE && ansible-playbook playbooks/site.yml"
}

run_tests() {
  log "Verification tests"
  if [ "${FULL:-}" = "1" ]; then
    ssh control01 'bash -s -- --full' < "$ROOT/scripts/test-lab.sh"
  else
    ssh control01 'bash -s' < "$ROOT/scripts/test-lab.sh"
  fi
}