# Runbook: connect a Linux client to the company VPN

The VPN is WireGuard carried inside TLS on TCP 443 by wstunnel, because
WireGuard's own UDP traffic is dropped on some networks (INC-001).

## One-time setup
1. Generate a WireGuard key pair and give the admin the public key:
       sudo sh -c 'umask 077; wg genkey > /etc/wireguard/ahmed.key'
       sudo sh -c 'wg pubkey < /etc/wireguard/ahmed.key > /etc/wireguard/ahmed.pub'
2. The admin adds the public key to ansible/inventory/group_vars/role_gateway.yml
   and runs site.yml.
3. Install wstunnel (same version as the server, 11.1.0) into /usr/local/bin,
   owned by root, mode 0755.
4. Create /etc/wireguard/ahmed.conf:
       [Interface]
       PrivateKey = <contents of ahmed.key>
       Address = <your VPN address, for example 10.8.0.2/32>
       MTU = 1280

       [Peer]
       PublicKey = <cat /etc/wireguard/server.pub on gw01>
       Endpoint = 127.0.0.1:51820
       AllowedIPs = 10.0.0.0/16
       PersistentKeepalive = 25

## Connect
Terminal 1 (leave running):
    wstunnel client -L 'udp://127.0.0.1:51820:localhost:51820?timeout_sec=0' wss://<gateway_public_ip>:443
Terminal 2:
    sudo wg-quick up ahmed
    ping -c 3 10.0.1.10

## Disconnect
    sudo wg-quick down ahmed     (then Ctrl-C in terminal 1)

## After a lab rebuild
The gateway's public IP and WireGuard server key change. Update the wstunnel
command with the new IP (`terraform output gateway_public_ip`) and PublicKey
with the new server.pub.

## Troubleshooting
- `sudo wg show ahmed`: no "latest handshake" means nothing came back.
- Terminal 1 should log "Opening TCP connection" and a TLS handshake.
- `timeout 5 bash -c '</dev/tcp/<gateway_public_ip>/443' && echo open`
  checks that TCP 443 is reachable.