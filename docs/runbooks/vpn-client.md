# Runbook: connect a Linux client to the company VPN

The VPN is WireGuard carried inside TLS on TCP 443 by wstunnel, because
WireGuard's own UDP traffic is dropped on some networks (INC-001).

## One-time setup
1. Install wireguard-tools, and wstunnel 11.1.0 into /usr/local/bin
   (owned by root, mode 0755).
2. Generate a WireGuard key pair:
       sudo sh -c 'umask 077; wg genkey > /etc/wireguard/ahmed.key'
       sudo sh -c 'wg pubkey < /etc/wireguard/ahmed.key > /etc/wireguard/ahmed.pub'
3. Add the public key (`sudo cat /etc/wireguard/ahmed.pub`) to
   ansible/inventory/group_vars/role_gateway.yml with your VPN address, and
   run site.yml.

## Daily use
    scripts/vpn-client.sh connect       start the tunnel and test it
    ssh control01-vpn                   reach control01 over the VPN
    scripts/vpn-client.sh status        show the tunnel state
    scripts/vpn-client.sh disconnect    stop the tunnel

`scripts/lab.sh up` runs `scripts/vpn-client.sh refresh` automatically, which
rewrites /etc/wireguard/ahmed.conf with the rebuilt gateway's key.

## Troubleshooting
- `sudo wg show ahmed`: no "latest handshake" means nothing came back.
- `journalctl --user -u ahmed-wstunnel` shows the wstunnel client log.
- `timeout 5 bash -c '</dev/tcp/<gateway_public_ip>/443' && echo open`
  checks that TCP 443 is reachable.
- Instance Connect still works if the VPN does not: `ssh control01`.