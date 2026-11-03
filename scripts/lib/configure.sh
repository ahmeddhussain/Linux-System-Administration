# shellcheck shell=bash
# Configuring the hosts with Ansible, and verifying the result.

load_agent_key() {
  # control01 borrows this key once per rebuild to create the ansible account.
  local rc=0
  ssh-add -l > /dev/null 2>&1 || rc=$?
  [ "$rc" -ne 2 ] || die 'No ssh-agent is running. Start one with: eval "$(ssh-agent)"  then retry.'
  ssh-add "$KEY"
}

# run_on_control01 <name> <command>: run a long command on control01 detached
# from this SSH session, then follow it with short SSH calls. A long session
# through the Instance Connect tunnel stalled on 2026-11-02 (the playbook
# finished on control01, but this side never saw the end); INC-002 may have
# been the same. Output: ~/run-<name>.log, exit code: ~/run-<name>.rc.
run_on_control01() {
  local name="$1" cmd="$2" rc="" seen=0 lines
  ssh control01 "rm -f ~/run-$name.rc; setsid nohup bash -c '$cmd > ~/run-$name.log 2>&1; echo \$? > ~/run-$name.rc' > /dev/null 2>&1 < /dev/null &" < /dev/null
  while [ -z "$rc" ]; do
    sleep 20
    # Progress: new task and play headers since the last look.
    lines="$(ssh control01 "grep -cE '^(PLAY|TASK) \[' ~/run-$name.log 2>/dev/null || echo 0" < /dev/null || echo "$seen")"
    if [ "$lines" -gt "$seen" ] 2> /dev/null; then
      ssh control01 "grep -E '^(PLAY|TASK) \[' ~/run-$name.log | tail -n +$((seen + 1)) | cut -c1-100" < /dev/null || true
      seen="$lines"
    fi
    rc="$(ssh control01 "cat ~/run-$name.rc 2>/dev/null" < /dev/null || true)"
  done
  ssh control01 "sed -n '/PLAY RECAP/,\$p' ~/run-$name.log; grep -E '^(PASS|FAIL|==|Result)' ~/run-$name.log" < /dev/null || true
  return "$rc"
}

configure_hosts() {
  log "Creating the ansible account on every host (one-time key forwarding)"
  ssh -A control01 "$REMOTE_ANSIBLE && ansible-playbook playbooks/bootstrap.yml -e ansible_user=ec2-user"
  log "Patching and configuring every host (site.yml; the first run takes a while)"
  run_on_control01 site "$REMOTE_ANSIBLE && ansible-playbook playbooks/site.yml"
}

# OpenSCAP scan of every host, results published on util01 (D-064).
run_compliance() {
  log "Compliance scan (OpenSCAP CIS Level 1; several minutes)"
  run_on_control01 compliance "$REMOTE_ANSIBLE && ansible-playbook playbooks/compliance.yml"
}

run_tests() {
  log "Verification tests"
  ssh control01 'cat > ~/test-lab.sh' < "$ROOT/scripts/test-lab.sh"
  if [ "${FULL:-}" = "1" ]; then
    run_on_control01 tests 'bash ~/test-lab.sh --full'
  else
    run_on_control01 tests 'bash ~/test-lab.sh'
  fi
}