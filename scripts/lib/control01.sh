# shellcheck shell=bash
# Reaching and preparing control01.

write_ssh_config() {
  log "Writing SSH entries for control01"
  local id
  id="$(instance_id control01)"
  [ -n "$id" ] || die "control01 is not running."
  # control01      : through AWS Instance Connect (always works, break-glass)
  # control01-vpn  : over the VPN; host key stored under the instance ID, so a
  #                  rebuilt control01 at the same IP is not confused with the old one
  cat > "$SSH_INCLUDE" << EOF
Host control01
  HostName $id
  User ec2-user
  IdentityFile $KEY
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ProxyCommand aws ec2-instance-connect open-tunnel --instance-id %h --region $REGION

Host control01-vpn
  HostName 10.0.1.10
  HostKeyAlias $id
  User ec2-user
  IdentityFile $KEY
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
}

wait_for_control01() {
  log "Waiting for control01 (the first boot can take several minutes)"
  local i
  for i in $(seq 1 60); do
    if ssh -o ConnectTimeout=10 -o BatchMode=yes control01 true 2> /dev/null; then
      echo "control01 is reachable."
      return 0
    fi
    sleep 15
  done
  die "control01 was not reachable after 15 minutes."
}

setup_control01() {
  log "Preparing control01 (packages, venv, collections, key, repo)"
  ssh control01 'bash -s' < "$ROOT/scripts/control01-setup.sh"
}

reboot_control01_if_needed() {
  # The patch play never reboots the machine it runs on, so do it from here.
  local rc
  rc="$(ssh control01 'dnf needs-restarting -r > /dev/null 2>&1; echo $?')"
  if [ "$rc" = "1" ]; then
    log "control01 needs a reboot after patching; rebooting it now"
    ssh control01 'sudo systemctl reboot' || true
    sleep 30
    wait_for_control01
  fi
}