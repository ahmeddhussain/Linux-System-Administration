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
  trap 'vpn_peers_down; rm -rf "$keydir"' EXIT
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
  # web <user> <host-ip> <url> <200|403|000> [proxy-port]: the proxy's answer
  # to CONNECT, from that user's login shell (so ahmed-proxy.sh applies).
  # 200 allowed, 403 denied by policy, 000 connection refused (nftables).
  web() {
    local got proxy=""
    [ -n "${5:-}" ] && proxy="-x http://util01.ahmed.internal:$5"
    got="$(ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o IdentitiesOnly=yes -o ConnectTimeout=10 -i "$keydir/$1" "$1@$2" \
      "bash -lc 'curl -s -o /dev/null -m 10 $proxy -w %{http_connect} $3'" 2> /dev/null)"
    got="${got:-000}"
    if [ "$got" = "$4" ]; then
      echo "PASS  web $1@$2 $3${5:+ via :$5} -> $4"; pass=$((pass + 1))
    else
      echo "FAIL  web $1@$2 $3${5:+ via :$5} expected $4, got $got"; fail=$((fail + 1))
    fi
  }

  # remote_check "description" <inventory-host> <command>: PASS when the
  # command succeeds there as root (no extra shell layer, so plain quoting)
  remote_check() {
    if ansible "$2" -b -m shell -a "$3" > /dev/null 2>&1; then
      echo "PASS  $1"; pass=$((pass + 1))
    else
      echo "FAIL  $1"; fail=$((fail + 1))
    fi
  }

  # as_check "description" <user> <host-ip> <command>: PASS when the command
  # succeeds in that user's login session
  as_check() {
    if as_user "$2" "$3" "bash -lc '$4'"; then
      echo "PASS  $1"; pass=$((pass + 1))
    else
      echo "FAIL  $1"; fail=$((fail + 1))
    fi
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

  # Per-team VPN test peers (D-055): one per team, inside a network namespace
  # on control01, carried by wstunnel to gw01:443 like a real client.
  VPN_TEAMS="admin dev ops"
  vpn_peers_up() {
    local gw_pub i=0 team port ns wg
    gw_pub="$(python3 -c 'import yaml; print(yaml.safe_load(open("inventory/group_vars/role_gateway/main.yml"))["wireguard_server_public_key"])')"
    ansible-vault view ../ansible/tests/test-vpn-peers.vault.yml 2> /dev/null \
      | python3 -c 'import os, sys, yaml
for t, k in yaml.safe_load(sys.stdin)["test_vpn_peer_private_keys"].items():
    with open(os.open(os.path.join(sys.argv[1], "wg-" + t), os.O_WRONLY | os.O_CREAT, 0o600), "w") as f:
        f.write(k)' "$keydir"
    for team in $VPN_TEAMS; do
      port=$((51821 + i)); ns="vpnt-$team"; wg="wgt-$team"
      nohup /usr/local/bin/wstunnel client \
        -L "udp://127.0.0.1:$port:localhost:51820?timeout_sec=0" "wss://10.0.0.10:443" \
        > /dev/null 2>&1 &
      echo $! >> "$keydir/wstunnel.pids"
      sudo ip netns add "$ns"
      # Created here (its socket stays in this namespace and can reach
      # wstunnel on localhost), then moved into the test namespace.
      sudo ip link add "$wg" type wireguard
      sudo wg set "$wg" private-key "$keydir/wg-$team" peer "$gw_pub" \
        endpoint "127.0.0.1:$port" allowed-ips 10.0.0.0/16,10.8.0.1/32 persistent-keepalive 5
      sudo ip link set "$wg" netns "$ns"
      sudo ip -n "$ns" addr add "10.8.$i.250/32" dev "$wg"
      sudo ip -n "$ns" link set lo up
      sudo ip -n "$ns" link set "$wg" up
      sudo ip -n "$ns" route add 10.0.0.0/16 dev "$wg"
      sudo ip -n "$ns" route add 10.8.0.1/32 dev "$wg"
      i=$((i + 1))
    done
    sleep 3
  }
  vpn_peers_down() {
    local team
    for team in $VPN_TEAMS; do sudo ip netns del "vpnt-$team" 2> /dev/null; done
    [ -f "$keydir/wstunnel.pids" ] && xargs -r kill < "$keydir/wstunnel.pids" 2> /dev/null
    rm -f "$keydir/wstunnel.pids"
  }
  # vpn <team> <ip> <port|ping> <open|blocked>: test from that team's peer
  vpn() {
    local got=blocked cmd
    if [ "$3" = ping ]; then cmd="ping -c 2 -W 2 $2"; else cmd="timeout 4 bash -c '</dev/tcp/$2/$3'"; fi
    sudo ip netns exec "vpnt-$1" bash -c "$cmd" > /dev/null 2>&1 && got=open
    if [ "$got" = "$4" ]; then
      echo "PASS  vpn $1 -> $2 $3 is $4"; pass=$((pass + 1))
    else
      echo "FAIL  vpn $1 -> $2 $3 expected $4, got $got"; fail=$((fail + 1))
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
  check "sshd effective settings are hardened"     "ansible all -b -m shell -a '[ \$(sshd -T | grep -cE \"^(permitrootlogin no|passwordauthentication no|kbdinteractiveauthentication no|gssapiauthentication no|maxauthtries 4)\$\") -eq 5 ]'"
  check "clocks are synchronized"                  "ansible all -b -m shell -a 'chronyc tracking | grep -q \"Leap status.*Normal\"'"
  check "password login is refused"                "$ssh_probe -o PreferredAuthentications=password -o PubkeyAuthentication=no ansible@10.0.2.10 true 2>&1 | grep -q 'Permission denied'"
  # INC-007: the server must offer public keys and nothing else (IPA's
  # drop-in had turned keyboard-interactive and GSSAPI back on).
  check "servers offer only public-key login"     "for ip in 10.0.0.10 10.0.1.11 10.0.1.12 10.0.2.10 10.0.2.11; do $ssh_probe -o PubkeyAuthentication=no ansible@\$ip true 2>&1 | grep -q 'Permission denied (publickey)' || exit 1; done"
  check "PAM: company authselect profile (faillock, history, no empty passwords)" "ansible all -b -m shell -a 'authselect current -r | grep -qE \"^custom/ahmed .*with-faillock\" && authselect current -r | grep -q without-nullok && authselect check'"
  check "nobody may use su (empty sugroup)"        "ansible all -b -m shell -a 'grep -q \"pam_wheel.so use_uid group=sugroup\" /etc/pam.d/su && test -z \"\$(getent group sugroup | cut -d: -f4)\"'"
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
  check "wg0 is in the vpn firewall zone"          "ansible gw01 -b -m shell -a 'test \"\$(firewall-cmd --get-zone-of-interface=wg0)\" = vpn'"
  check "IPv4 forwarding is enabled"               "ansible gw01 -b -m shell -a 'test \$(sysctl -n net.ipv4.ip_forward) = 1'"
  check "no other host forwards packets (D-064)"   "ansible 'all:!gw01' -b -m shell -a 'test \$(sysctl -n net.ipv4.ip_forward) = 0'"
  check "per-team forwarding policies are active"  "ansible gw01 -b -m shell -a 'p=\$(firewall-cmd --get-active-policies); for t in admin dev ops; do echo \"\$p\" | grep -qw vpn-\$t-to-vpc || exit 1; done; ! echo \"\$p\" | grep -qw vpn_to_vpc'"
  check "wstunnel is active"                       "ansible gw01 -b -m shell -a 'systemctl is-active --quiet wstunnel'"
  check "wstunnel listens on TCP 443"              "ansible gw01 -b -m shell -a 'ss -Htln sport = :443 | grep -q .'"
  check "WireGuard UDP port is closed to the outside" "ansible gw01 -b -m shell -a '! firewall-cmd --zone=public --list-ports | grep -qw 51820/udp'"

  echo "== util01 data volume and backups (D-056)"
  check "util01 data areas are mounted from vg_data" "ansible util01 -m shell -a 'findmnt -n -o SOURCE /export/home | grep -q vg_data-lv_home && findmnt -n -o SOURCE /srv/logs | grep -q vg_data-lv_logs'"
  check "util01 backup timer is active"            "ansible util01 -b -m shell -a 'systemctl is-active --quiet ahmed-backup.timer'"
  check "util01 can back up to S3"                 "ansible util01 -b -m command -a '/usr/local/sbin/ahmed-backup backup'"
  check "the latest backup is readable"            "ansible util01 -b -m command -a '/usr/local/sbin/ahmed-backup verify'"

  echo "== Time and identity (FreeIPA on idm01)"
  check "every host syncs time from AWS (Kerberos needs it)" "ansible all -b -m shell -a 'chronyc -n sources | grep -q \"^\\^\\* 169.254.169.123\"'"
  check "every IPA service is running on idm01"    "ansible idm01 -b -m shell -a 'ipactl status'"
  check "IPA DNS resolves hosts (gw01 from ws-dev01)" "ansible ws-dev01 -m shell -a 'test \"\$(dig +short gw01.ahmed.internal)\" = 10.0.0.10'"
  check "names outside ahmed.internal still resolve" "ansible ipaclients -m shell -a 'getent hosts cdn.redhat.com'"
  check "every client is enrolled (host keytab)"   "ansible ipaclients -b -m shell -a 'klist -k /etc/krb5.keytab | grep -q host/'"
  check "SSSD resolves IPA accounts on every client" "ansible ipaclients -m shell -a 'id admin'"
  check "IPA user and group IDs match identity.yml (D-060)" "python3 -c '
import grp, pwd, sys, yaml
d = yaml.safe_load(open(\"inventory/group_vars/role_idm/identity.yml\"))
bad = [u[\"name\"] for u in d[\"ipa_users\"] if pwd.getpwnam(u[\"name\"]).pw_uid != u[\"uid\"]]
bad += [g[\"name\"] for g in d[\"ipa_groups\"] if grp.getgrnam(g[\"name\"]).gr_gid != g[\"gid\"]]
sys.exit(1 if bad else 0)'"
  check "SSSD is online on every client"           "ansible ipaclients -b -m shell -a 'sssctl domain-status ahmed.internal -o | grep -q \"Online status: Online\"'"
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

  echo "== Central logs over TLS on util01 (D-059)"
  check "every host has a valid IPA certificate for rsyslog" "ansible all -b -m shell -a 'ipa-getcert list -i rsyslog | grep -q \"status: MONITORING\"'"
  logtoken="logcheck-$(date +%s)"
  ansible all -m command -a "logger -t ahmed-logtest $logtoken" > /dev/null 2>&1
  logger -n util01.ahmed.internal -P 6514 -T -t ahmed-plaintest "plain-$logtoken" 2> /dev/null
  sleep 8
  check "a message from every host arrives on util01" "ansible util01 -b -m shell -a 'test \$(grep -l $logtoken /srv/logs/*/ahmed-logtest.log | wc -l) = 6'"
  check "plain (non-TLS) syslog is not stored"       "ansible util01 -b -m shell -a '! ls /srv/logs/*/ahmed-plaintest.log'"
  as_check "the security team (laila) can read the logs" laila 10.0.1.12 "grep -q $logtoken /srv/logs/*/ahmed-logtest.log"
  as_check "other teams (sara) cannot"                   sara  10.0.1.12 "! cat /srv/logs/*/ahmed-logtest.log"

  echo "== Audit records on every host, central on util01 (D-063)"
  check "audit rules are loaded on every host" "ansible all -b -m shell -a 'auditctl -l | grep -q key=privileged && auditctl -l | grep -q -e \"-k identity\"'"
  # Match the program field only: Ansible logs every command line it runs,
  # so the word itself appears in messages from earlier checks.
  remote_check "audit records stay out of /var/log/messages" all '! grep -qE "^[A-Z][a-z]{2} +[0-9]+ [0-9:]+ [^ ]+ audisp-syslog[:[]" /var/log/messages'
  audittoken="auditcheck-$(date +%s)"
  as_user sara 10.0.2.11 "sudo -n /usr/bin/echo $audittoken"
  ansible ws-dev01 -b -m command -a 'touch /etc/ssh/sshd_config' > /dev/null 2>&1
  sleep 8
  # Central directories are named by reverse DNS, i.e. the FQDN (D-059).
  central="ausearch -if /srv/logs"
  remote_check "sara's sudo on ws-ops01 is on util01 (USER_CMD)" util01 "$central/ws-ops01.ahmed.internal/audit.log -m USER_CMD --start recent -i | grep -q $audittoken"
  remote_check "... and her root command (key privileged)"       util01 "$central/ws-ops01.ahmed.internal/audit.log -k privileged --start recent -i | grep -q $audittoken"
  remote_check "a change to sshd_config on ws-dev01 is found by key" util01 "$central/ws-dev01.ahmed.internal/audit.log -k sshd --start recent > /dev/null"
  remote_check "Ansible's own root commands are not in privileged" util01 "! $central/ws-dev01.ahmed.internal/audit.log -k privileged --start recent -i 2> /dev/null | grep -q 'auid=ansible'"
  as_check "the security team (laila) can search them"   laila 10.0.1.12 "sudo -n $central/ws-ops01.ahmed.internal/audit.log -k privileged --start recent > /dev/null"
  as_check "other teams (sara) cannot read them"          sara  10.0.1.12 "! cat /srv/logs/ws-ops01.ahmed.internal/audit.log"
  remote_check "sudo also writes its own log (/var/log/sudo.log)" ws-ops01 "grep -q $audittoken /var/log/sudo.log"
  check "today's audit report is written" "ansible util01 -b -m shell -a 'systemctl start ahmed-audit-report.service && grep -q \"==== ws-ops01.ahmed.internal\" /srv/logs/reports/audit-\$(date +%F).txt'"
  as_check "... and the security team can read it"       laila 10.0.1.12 'test -r /srv/logs/reports/audit-$(date +%F).txt'

  echo "== OpenSCAP compliance, CIS Level 1 (D-064)"
  oscap_dir=/srv/logs/reports/openscap
  remote_check "every host has an OpenSCAP result on util01 from today" util01 "test \$(find $oscap_dir -name results.xml.gz -mtime -1 | wc -l) = 6"
  remote_check "every host meets its role's minimum score" util01 "f=$oscap_dir/summary.txt; test \$(grep -vc '^#' \$f) = 6 && awk '!/^#/ && \$2 < \$3 {bad=1} END {exit bad}' \$f"
  as_check "the security team (laila) can read the reports" laila 10.0.1.12 "test -r $oscap_dir/summary.txt"

  echo "== NFS home directories (D-058): util01 -> workstations"
  check "util01 exports homes, NFSv4 only"          "ansible util01 -b -m shell -a 'exportfs -s | grep -q /export/home && grep -q -- -3 /proc/fs/nfsd/versions'"
  as_check "ahmed's home on ws-dev01 is NFS at /users/ahmed" ahmed 10.0.2.10 'test "$PWD" = /users/ahmed && findmnt -n -o FSTYPE -T . | grep -q nfs4'
  as_check "sara's home on ws-ops01 is NFS"          sara  10.0.2.11 'findmnt -n -o FSTYPE -T ~ | grep -q nfs4'
  token="nfs-check-$(date +%s)"
  as_check "a file written on ws-dev01 ..."          ahmed.admin 10.0.2.10 "echo $token > ~/.nfs-check"
  as_check "... is readable on ws-ops01 (same home)" ahmed.admin 10.0.2.11 "grep -q $token ~/.nfs-check"
  check "root on a workstation cannot read another user's home (root_squash)" "ansible ws-ops01 -b -m shell -a '! ls /users/sara'"
  as_check "servers keep local homes (idm01)"        ahmed.admin 10.0.1.11 '! findmnt -n -T ~ -o FSTYPE | grep -q nfs'

  echo "== Storage on util01, quotas and team shares (D-061)"
  remote_check "vg_data spans both data disks"     util01 'test $(pvs --noheadings -S vg_name=vg_data | wc -l) = 2'
  remote_check "lv_home is 12G, lv_teams 8G"        util01 'lvs --noheadings --units g --nosuffix -o lv_size vg_data/lv_home | grep -q "12.00" && lvs --noheadings --units g --nosuffix -o lv_size vg_data/lv_teams | grep -q "8.00"'
  remote_check "workstations keep only a 10 GiB OS disk" role_workstation 'test $(lsblk -bdno SIZE /dev/nvme0n1) -le 10737418240'
  remote_check "home and team quotas are enforced"  util01 'xfs_quota -x -c "state -u" /export/home | grep -q "Enforcement: ON" && xfs_quota -x -c "state -p" /export/teams | grep -q "Enforcement: ON"'
  as_check "contractor1 cannot exceed a 50 MB home quota" contractor1 10.0.2.10 '! dd if=/dev/zero of=~/quota-test bs=1M count=60 status=none conv=fsync; rm -f ~/quota-test'
  as_check "ahmed writes in /teams/dev ..."          ahmed 10.0.2.10 'head -c 5M /dev/zero > /teams/dev/quota-check && test "$(stat -c %G /teams/dev/quota-check)" = dev'
  # The ACL lives on util01's filesystem; NFSv4 does not show POSIX ACLs to
  # the client, so check it there. "mask::rw" = the team can write it even
  # though the creator's umask (022) would have made it read-only.
  remote_check "... new files stay writable by the team (default ACL)" util01 'getfacl -p /export/teams/dev/quota-check | grep -q "^group:dev:rwx" && getfacl -p /export/teams/dev/quota-check | grep -q "^mask::rw"'
  remote_check "... and count against dev's project quota" util01 'test "$(xfs_quota -x -c "report -p -N -b" /export/teams | awk "\$1 == \"dev\" {print \$2}")" -ge 5120'
  as_check "ops cannot enter dev's directory"        sara  10.0.2.11 '! ls /teams/dev'
  as_check "sara writes in the company share ..."    sara  10.0.2.11 'echo hi > /teams/company/from-sara'
  as_check "... ahmed reads it ..."                   ahmed 10.0.2.10 'grep -q hi /teams/company/from-sara'
  as_check "... but cannot delete it (sticky bit)"   ahmed 10.0.2.10 '! rm -f /teams/company/from-sara'
  as_user ahmed 10.0.2.10 'rm -f /teams/dev/quota-check'
  as_user sara 10.0.2.11 'rm -f /teams/company/from-sara'

  echo "== Web access through Squid (D-057): standard vs allow-list, per user"
  check "Squid listens on util01 (3128, 3129)"     "ansible util01 -b -m shell -a 'ss -Htln sport = :3128 | grep -q . && ss -Htln sport = :3129 | grep -q .'"
  check "dnf on workstations works through the proxy" "ansible role_workstation -b -m shell -a 'dnf -q makecache --refresh'"
  check "workstations cannot reach the web directly" "ansible role_workstation -m shell -a '! curl -s -m 5 --noproxy \"*\" -o /dev/null https://example.com'"
  check "servers still reach the web directly"     "ansible util01 -m shell -a 'curl -s -m 5 -o /dev/null https://example.com'"
  web ahmed       10.0.2.10 https://example.com      200
  web ahmed       10.0.2.10 https://chatgpt.com      200
  web ahmed       10.0.2.10 https://www.youtube.com  403
  web ahmed       10.0.2.10 https://www.facebook.com 403
  web sara        10.0.2.11 https://example.com      200
  web sara        10.0.2.11 https://www.reddit.com   403
  web contractor1 10.0.2.10 https://github.com       200
  web contractor1 10.0.2.10 https://example.com      403
  web contractor1 10.0.2.10 https://example.com      000 3128
  web omar        10.0.2.11 https://pypi.org         200
  web omar        10.0.2.11 https://example.com      403
  web omar        10.0.2.11 https://example.com      000 3128
  check "per-user rule survives a firewalld reload" "ansible role_workstation -b -m shell -a 'firewall-cmd --reload >/dev/null && nft list table inet ahmed_proxy >/dev/null'"

  echo "== Per-team VPN policy (test peers through wstunnel; gw01 firewall + security groups)"
  vpn_peers_up
  # gw01's tunnel address 10.8.0.1: ping for everyone, SSH for admin only (D-054)
  vpn admin 10.8.0.1  22   open
  vpn dev   10.8.0.1  22   blocked
  vpn ops   10.8.0.1  22   blocked
  vpn dev   10.8.0.1  ping open
  # admin: control01, workstations, IPA web UI; servers only via control01
  vpn admin 10.0.1.10 22   open
  vpn admin 10.0.1.10 ping open
  vpn admin 10.0.2.10 22   open
  vpn admin 10.0.2.11 22   open
  vpn admin 10.0.1.11 443  open
  vpn admin 10.0.1.11 22   blocked
  vpn admin 10.0.1.12 22   blocked
  # dev: ws-dev01 only
  vpn dev   10.0.2.10 22   open
  vpn dev   10.0.2.11 22   blocked
  vpn dev   10.0.1.10 22   blocked
  vpn dev   10.0.1.11 22   blocked
  vpn dev   10.0.2.10 ping blocked
  # ops: ws-ops01 and the servers idm01, util01 (D-053)
  vpn ops   10.0.2.11 22   open
  vpn ops   10.0.1.11 22   open
  vpn ops   10.0.1.12 22   open
  vpn ops   10.0.2.10 22   blocked
  vpn ops   10.0.1.10 22   blocked
  vpn ops   10.0.1.11 443  blocked
  vpn_peers_down

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