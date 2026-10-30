# INC-001: VPN clients cannot complete the WireGuard handshake

| Field | Value |
|---|---|
| Date | 2026-10-30 |
| Severity | Medium: remote VPN access unavailable; admin access unaffected |
| Status | Open, mitigated (admin access through the Instance Connect break-glass path) |
| Systems | gw01 (WireGuard gateway), admin client (VMware VM and Windows host) |

## Summary
After the WireGuard gateway was deployed, the admin client could not keep a
tunnel up. Ping to control01 over the VPN failed almost every time, with a few
brief successes. Investigation showed that gw01 received and answered every
handshake, but the answers never reached the client. A controlled test on the
same port and path showed that plain UDP traffic made the round trip while
WireGuard traffic did not. The most likely cause is filtering of WireGuard
traffic somewhere on the network path between AWS and the client.

## Impact
- Employees and the admin could not use the VPN from the affected network.
- Admin access continued through the EC2 Instance Connect Endpoint
  (HTTPS to AWS), so no configuration work was blocked.

## Timeline (local time, UTC+2)
| Time | Event |
|---|---|
| 17:16 | Tunnel brought up on the client; ping fails; client shows 0 B received |
| 17:18 | Found `admin_cidr` still set to the documentation example `203.0.113.10/32`; corrected to the real address and applied |
| 17:22 | Still failing; capture on gw01 shows no packets arriving |
| 17:24 | Security group rule verified: UDP 51820 allowed from the client address |
| 17:29 | Elastic IP verified attached to gw01 |
| 17:30 | Single success: handshake completes, 3 pings answered |
| 17:35 | Tunnel silent again; only 572 B ever received |
| 17:39 | VPN port opened to any address to rule out an address mismatch; still failing |
| 17:44 | gw01 capture shows the client's real source address equals the expected one; address theory disproved |
| 17:47 | Simultaneous captures: client sent 26 handshake initiations; gw01 received and answered every one; the client received none |
| 17:55 | Same failure with the WireGuard client on the Windows host directly; VMware NAT ruled out |
| 18:04 | Test from a mobile hotspot also fails (capture timing not verified, so treated as inconclusive) |
| 18:15 | Controlled test: plain UDP echo on the same port and path makes a full round trip |

## Investigation
Each layer was tested in isolation, with evidence:

| Layer | Test | Result |
|---|---|---|
| Keys | Compared public keys on client and server | Match |
| AWS security group | Listed inbound rules | Correct |
| Elastic IP | Checked association | Attached to gw01 |
| gw01 WireGuard | Packet capture on gw01 | Every handshake received and answered |
| Client VM and VMware | Same tunnel run directly on the Windows host | Same failure |
| Network path, generic UDP | Echo service on UDP 51820 instead of WireGuard | Round trip succeeds |
| Network path, WireGuard | Handshake responses (92-byte packets) | Not delivered |

## Root cause
Most likely, filtering on the network path that recognizes WireGuard traffic
(its handshake messages have fixed sizes and header bytes) and drops it,
mainly the responses from the server. The exact location of the filter is
unknown. Confidence: high that the problem is specific to WireGuard traffic,
since everything else on the same path was shown to work.

## Defects found along the way (fixed)
- `admin_cidr` left at the example value.
- Peer file named `role-gateway.yml` instead of `role_gateway.yml`, so Ansible
  ignored it; the role then started a tunnel with no peers.
- An SSH public key path used where a WireGuard key was required.
- wg0 bound to the trusted firewall zone at runtime only, lost after reloads.

## What went well
- The Instance Connect break-glass path kept admin access available.
- Packet captures on both ends made each conclusion evidence-based.

## What went wrong
- An early hypothesis (changing client address) was acted on before being
  verified, which led to an unnecessary rule change and a wrong rationale in
  D-039.
- Tests at first were run without controlling timing and conditions.

## Action items
| Action | Status |
|---|---|
| Fail the WireGuard role when no peers are defined | Done |
| Bind wg0 to the trusted zone permanently | Done |
| Correct the rationale of D-039 | Done |
| Choose and implement a VPN transport that passes the filter | Open |
| Add a client-side connectivity test to the verification script | Open |