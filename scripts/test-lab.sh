#!/usr/bin/env bash
# Runs on control01. Usage from your laptop, in the repo directory:
#   scripts/lab.sh verify            (fast checks)
#   scripts/lab.sh verify --full     (adds the slow idempotency run)

main() {
  local full="no"
  [ "${1:-}" = "--full" ] && full="yes"
  local pass=0 fail=0

  cd "$HOME/ahmed-infra/ansible" || exit 1
  # shellcheck disable=SC1091
  source "$HOME/ansible-venv/bin/activate"

  # These checks test how a server treats a login attempt, not who the server
  # is, so they ignore remembered host keys.
  local ssh_probe="ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

  # check "description" "command"  -> PASS when the command succeeds
  check() {
    if timeout 300 bash -c "$2" > /dev/null 2>&1; then
      echo "PASS  $1"; pass=$((pass + 1))
    else
      echo "FAIL  $1"; fail=$((fail + 1))
    fi
  }

  # reach <from-host> <target-ip> <port> <open|blocked>
  reach() {
    local out
    out="$(ansible "$1" -m shell -a "timeout 3 bash -c '</dev/tcp/$2/$3' && echo open || echo blocked" -o 2>&1 || true)"
    if [[ "$out" == *"(stdout) $4"* ]]; then
      echo "PASS  $1 -> $2:$3 is $4"; pass=$((pass + 1))
    else
      echo "FAIL  $1 -> $2:$3 expected $4"; fail=$((fail + 1))
    fi
  }

  echo "== Inventory and access"
  check "dynamic inventory finds 6 hosts"          "ansible all --list-hosts | grep -q 'hosts (6)'"
  check "all hosts answer as the ansible account"  "ansible all -m ping"
  check "passwordless sudo works on all hosts"     "[ \"\$(ansible all -b -m command -a whoami -o | grep -c root)\" = 6 ]"
  check "hostnames are FQDNs in ahmed.internal"    "[ \"\$(ansible all -m command -a 'hostnamectl --static' -o | grep -c 'ahmed.internal')\" = 6 ]"

  echo "== Network policy (default deny)"
  check "control01 reaches the internet on 443"    "curl -sI -m 8 https://aws.amazon.com"
  check "control01 is blocked on port 80"          "! curl -sI -m 5 http://example.com"
  reach control01 10.0.1.11 22 open
  reach control01 10.0.1.12 22 open
  reach control01 10.0.2.10 22 open
  reach control01 10.0.0.10 22 open
  reach gw01      10.0.1.11 22 blocked
  reach gw01      10.0.1.10 22 blocked
  reach ws-dev01  10.0.1.11 22 blocked
  reach ws-dev01  10.0.1.12 22 blocked
  reach ws-dev01  10.0.2.11 22 blocked
  reach ws-ops01  10.0.2.10 22 blocked

  echo "== Baseline configuration"
  check "SELinux is enforcing everywhere"          "[ \"\$(ansible all -b -m command -a getenforce -o | grep -c Enforcing)\" = 6 ]"
  check "firewalld, chronyd, sshd active everywhere" "ansible all -b -m shell -a 'for s in firewalld chronyd sshd; do systemctl is-active --quiet \$s || exit 1; done'"
  check "sshd effective settings are hardened"     "ansible all -b -m shell -a '[ \$(sshd -T | grep -cE \"^(permitrootlogin no|passwordauthentication no|maxauthtries 4)\$\") -eq 3 ]'"
  check "clocks are synchronized"                  "ansible all -b -m shell -a 'chronyc tracking | grep -q \"Leap status.*Normal\"'"
  check "password login is refused"                "$ssh_probe -o PreferredAuthentications=password -o PubkeyAuthentication=no ansible@10.0.2.10 true 2>&1 | grep -q 'Permission denied'"
  check "root login is refused"                    "$ssh_probe -i ~/.ssh/ansible_ed25519 root@10.0.2.10 true 2>&1 | grep -q 'Permission denied'"
  check "login banner is shown"                    "$ssh_probe ansible@10.0.2.10 true 2>&1 | grep -q 'Authorized access only'"

  echo "== Patch level"
  check "systemd is the same version everywhere"   "[ \"\$(ansible all -m command -a \"rpm -q --qf '%{VERSION}-%{RELEASE}' systemd\" -o | sed 's/.*(stdout) //' | sort -u | wc -l)\" = 1 ]"
  check "openssl-libs is the same version everywhere" "[ \"\$(ansible all -m command -a \"rpm -q --qf '%{VERSION}-%{RELEASE}' openssl-libs\" -o | sed 's/.*(stdout) //' | sort -u | wc -l)\" = 1 ]"
  check "no host needs a reboot"                   "ansible all -b -m command -a 'dnf needs-restarting -r'"

  echo "== VPN gateway (gw01)"
  check "wg-quick@wg0 is active"                   "ansible gw01 -b -m shell -a 'systemctl is-active --quiet wg-quick@wg0'"
  check "wg0 has at least one peer"                "ansible gw01 -b -m shell -a 'wg show wg0 peers | grep -q .'"
  check "wg0 is in the trusted firewall zone"      "ansible gw01 -b -m shell -a 'firewall-cmd --get-active-zones | grep -q wg0'"
  check "IPv4 forwarding is enabled"               "ansible gw01 -b -m shell -a 'test \$(sysctl -n net.ipv4.ip_forward) = 1'"
  check "vpn_to_vpc forwarding policy exists"      "ansible gw01 -b -m shell -a 'firewall-cmd --get-policies | grep -qw vpn_to_vpc'"
  check "wstunnel is active"                       "ansible gw01 -b -m shell -a 'systemctl is-active --quiet wstunnel'"
  check "wstunnel listens on TCP 443"              "ansible gw01 -b -m shell -a 'ss -Htln sport = :443 | grep -q .'"
  check "WireGuard UDP port is closed to the outside" "ansible gw01 -b -m shell -a '! firewall-cmd --zone=public --list-ports | grep -qw 51820/udp'"

  if [ "$full" = "yes" ]; then
    echo "== Idempotency (slow): a full site.yml run must change nothing"
    check "site.yml reports changed=0 on every host" "! ansible-playbook playbooks/site.yml | grep -qE 'changed=[1-9]'"
  fi

  echo
  echo "Result: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# Closing stdin stops commands inside from swallowing the rest of a script
# that was piped over SSH.
main "$@" < /dev/null