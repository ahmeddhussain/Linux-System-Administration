#!/usr/bin/env bash
# Laptop-side VPN client: WireGuard carried inside TLS by wstunnel.
#
# Usage:
#   scripts/vpn-client.sh refresh     rewrite the WireGuard config with the current gateway key
#   scripts/vpn-client.sh connect     start wstunnel and the tunnel, then test it
#   scripts/vpn-client.sh disconnect  stop both
#   scripts/vpn-client.sh status      show the tunnel state
#
# One-time setup: generate your key pair (docs/runbooks/vpn-client.md) and add
# your public key to ansible/inventory/group_vars/role_gateway.yml.
# Environment: LAB_WG_INTERFACE (default ahmed), LAB_WG_ADDRESS (default 10.8.0.2/32)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WG_IF="${LAB_WG_INTERFACE:-ahmed}"
WG_CONF="/etc/wireguard/${WG_IF}.conf"
WG_KEY="/etc/wireguard/${WG_IF}.key"
WG_ADDRESS="${LAB_WG_ADDRESS:-10.8.0.2/32}"
LOCAL_PORT=51820
UNIT="ahmed-wstunnel"

usage() {
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

cmd_refresh() {
  require_tools wg wg-quick terraform ssh
  sudo test -f "$WG_KEY" || die "Missing $WG_KEY. Generate your key pair first (docs/runbooks/vpn-client.md)."
  log "Fetching the gateway's WireGuard public key"
  local server_pub
  server_pub="$(ssh control01 "$REMOTE_ANSIBLE && ansible gw01 -b -m command -a 'cat /etc/wireguard/server.pub' -o 2> /dev/null" \
    | sed -n 's/.*(stdout) //p' | tr -d '[:space:]')"
  [[ "$server_pub" =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "Could not read the gateway's public key (got: '$server_pub')."

  log "Writing $WG_CONF"
  local private_key
  private_key="$(sudo cat "$WG_KEY")"
  sudo sh -c "umask 077; cat > '$WG_CONF'" << EOF
# Written by scripts/vpn-client.sh refresh. Rerun it after every lab rebuild.
[Interface]
PrivateKey = $private_key
Address = $WG_ADDRESS
MTU = 1280

[Peer]
PublicKey = $server_pub
Endpoint = 127.0.0.1:$LOCAL_PORT
AllowedIPs = 10.0.0.0/16
PersistentKeepalive = 25
EOF
  echo "Gateway key: $server_pub"
}

cmd_connect() {
  require_tools wstunnel wg-quick terraform systemd-run
  sudo test -f "$WG_CONF" || die "No $WG_CONF yet. Run: scripts/vpn-client.sh refresh"
  local gateway_ip wstunnel_bin
  gateway_ip="$(tf_output gateway_public_ip)"
  wstunnel_bin="$(command -v wstunnel)"

  cmd_disconnect > /dev/null 2>&1 || true

  log "Starting wstunnel to wss://$gateway_ip:443"
  systemd-run --user --collect --unit="$UNIT" "$wstunnel_bin" client \
    -L "udp://127.0.0.1:$LOCAL_PORT:localhost:51820?timeout_sec=0" "wss://$gateway_ip:443"
  sleep 2

  log "Bringing up WireGuard ($WG_IF)"
  sudo wg-quick up "$WG_IF"

  log "Testing: ping control01 over the VPN"
  if ping -c 3 -W 3 10.0.1.10 > /dev/null; then
    echo "Connected. Try: ssh control01-vpn"
  else
    warn "No reply from 10.0.1.10. Check: scripts/vpn-client.sh status"
    return 1
  fi
}

cmd_disconnect() {
  sudo wg-quick down "$WG_IF" 2> /dev/null || true
  systemctl --user stop "$UNIT" 2> /dev/null || true
  echo "Disconnected."
}

cmd_status() {
  systemctl --user --no-pager status "$UNIT" 2> /dev/null | head -n 3 || echo "wstunnel: not running"
  sudo wg show "$WG_IF" 2> /dev/null | grep -E 'endpoint|handshake|transfer' || echo "WireGuard: not up"
}

case "${1:-}" in
  refresh) cmd_refresh ;;
  connect) cmd_connect ;;
  disconnect) cmd_disconnect ;;
  status) cmd_status ;;
  *) usage ;;
esac