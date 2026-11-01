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

  # IPA test users: private keys from the vault, in memory only, removed on
  # exit. as_user <user> <ip> <command> logs in with that user's key.
  keydir="$(mktemp -d /dev/shm/test-keys.XXXXXX)"
  trap 'rm -rf "$keydir"' EXIT
  ansible-vault view ../ansible/tests/test-user-keys.vault.yml 2> /dev/null \
    | python3 -c 'import os, sys, yaml
for u, k in yaml.safe_load(sys.stdin)["test_user_private_keys"].items():
    p = os.path.join(sys.argv[1], u)
    with open(os.open(p, os.O_WRONLY | os.O_CREAT, 0o600), "w") as f:
        f.write(k)' "$keydir"
  as_user() {
    ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o IdentitiesOnly=yes -o ConnectTimeout=10 -i "$keydir/$1" "$1@$2" "$3" > /dev/null 2>&1
  }
  # login <user> <host-ip> <allowed|denied>
  login() {
    local got=denied
    as_user "$1" "$2" true && got=allowed
    if [ "$got" = "$3" ]; then
      echo "PASS  $1 login on $2 is $3"; pass=$((pass + 1))
    else
      echo "FAIL  $1 login on $2 expected $3, got $got"; fail=$((fail + 1))
    fi
  }
  # sudo_as <user> <host-ip> <command> <allowed|denied>
  sudo_as() {
    local got=denied
    as_user "$1" "$2" "sudo -n $3" && got=allowed
    if [ "$got" = "$4" ]; then
      echo "PASS  $1 sudo '$3' on $2 is $4"; pass=$((pass + 1))
    else
      echo "FAIL  $1 sudo '$3' on $2 expected $4, got $got"; fail=$((fail + 1))
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
  check "gateway key matches the one clients have" "ansible gw01 -b -m shell -a 'test \"\$(wg show wg0 public-key)\" = {{ wireguard_server_public_key }}'"
  check "wg0 is in the trusted firewall zone"      "ansible gw01 -b -m shell -a 'firewall-cmd --get-active-zones | grep -q wg0'"
  check "IPv4 forwarding is enabled"               "ansible gw01 -b -m shell -a 'test \$(sysctl -n net.ipv4.ip_forward) = 1'"
  check "vpn_to_vpc forwarding policy exists"      "ansible gw01 -b -m shell -a 'firewall-cmd --get-policies | grep -qw vpn_to_vpc'"
  check "wstunnel is active"                       "ansible gw01 -b -m shell -a 'systemctl is-active --quiet wstunnel'"
  check "wstunnel listens on TCP 443"              "ansible gw01 -b -m shell -a 'ss -Htln sport = :443 | grep -q .'"
  check "WireGuard UDP port is closed to the outside" "ansible gw01 -b -m shell -a '! firewall-cmd --zone=public --list-ports | grep -qw 51820/udp'"

  echo "== Time and identity (FreeIPA on idm01)"
  check "every host syncs time from AWS (Kerberos needs it)" "ansible all -b -m shell -a 'chronyc -n sources | grep -q \"^\\^\\* 169.254.169.123\"'"
  check "every IPA service is running on idm01"    "ansible idm01 -b -m shell -a 'ipactl status'"
  check "IPA DNS resolves hosts (gw01 from ws-dev01)" "ansible ws-dev01 -m shell -a 'test \"\$(dig +short gw01.ahmed.internal)\" = 10.0.0.10'"
  check "names outside ahmed.internal still resolve" "ansible ipaclients -m shell -a 'getent hosts cdn.redhat.com'"
  check "every client is enrolled (host keytab)"   "ansible ipaclients -b -m shell -a 'klist -k /etc/krb5.keytab | grep -q host/'"
  check "SSSD resolves IPA accounts on every client" "ansible ipaclients -m shell -a 'id admin'"
  check "SSHFP records published (ws-dev01)"       "ansible ws-dev01 -m shell -a 'dig +short SSHFP ws-dev01.ahmed.internal | grep -q .'"
  check "no default allow_all login rule"          "ansible idm01 -b -m shell -a 'export KRB5CCNAME=\$(mktemp -u); kinit -k && ! ipa hbacrule-show allow_all; rc=\$?; kdestroy; exit \$rc'"
  reach ws-dev01  10.0.1.11 88  open
  reach ws-dev01  10.0.1.12 389 blocked

  echo "== Logins and sudo per team (HBAC and sudo rules from identity.yml)"
  # Hosts: gw01 10.0.0.10, control01 10.0.1.10, idm01 10.0.1.11,
  # util01 10.0.1.12, ws-dev01 10.0.2.10, ws-ops01 10.0.2.11
  login   ahmed.admin 10.0.1.11 allowed
  sudo_as ahmed.admin 10.0.2.10 id allowed
  login   ahmed       10.0.2.10 allowed
  sudo_as ahmed       10.0.2.10 id denied
  login   ahmed       10.0.2.11 denied
  login   sara        10.0.2.11 allowed
  sudo_as sara        10.0.2.11 id allowed
  login   sara        10.0.1.12 allowed
  login   sara        10.0.2.10 denied
  login   sara        10.0.1.10 denied
  login   sara        10.0.0.10 denied
  login   omar        10.0.2.11 allowed
  sudo_as omar        10.0.2.11 id denied
  login   laila       10.0.1.12 allowed
  sudo_as laila       10.0.1.12 "journalctl -n 1" allowed
  sudo_as laila       10.0.1.12 id denied
  login   laila       10.0.2.10 denied
  login   contractor1 10.0.2.10 allowed
  sudo_as contractor1 10.0.2.10 id denied
  login   contractor1 10.0.1.12 denied

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