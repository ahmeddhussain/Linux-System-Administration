# INC-006: lab build failed, control01's IP taken by the Instance Connect Endpoint

| Field | Value |
|---|---|
| Date | 2026-11-03 |
| Severity | Low: fresh build stopped; no running services (lab was down) |
| Status | Resolved (D-062: explicit subnet CIDR reservation) |
| Systems | Terraform lab layer: control01, Instance Connect Endpoint, infra subnet |

## Summary
`scripts/lab.sh up` failed during `terraform apply`: creating control01
returned `InvalidIPAddress.InUse: Address 10.0.1.10 is in use`. The
Instance Connect Endpoint, created earlier in the same apply, had been
given 10.0.1.10 by AWS. The other five hosts were created; control01 was
not, so nothing could be configured.

## Impact
- Build stopped before any configuration. Five unconfigured instances and
  the NAT gateway ran briefly on credits until the partial lab was
  destroyed.
- No data at risk: util01 was new and empty; the last backup in S3 was
  untouched.

## Timeline (2026-11-03)
| Step | Event |
|---|---|
| Preflight | AWS identity, Free plan state, no leftover instances: all fine |
| `lab.sh up` | apply creates network, endpoint, five hosts; control01 fails with `InvalidIPAddress.InUse` |
| Investigation | network interface holding 10.0.1.10 is of type `ec2_instance_connect_endpoint` |
| Recovery | `lab.sh down` (backup skipped: no control01, util01 empty); teardown confirmed |
| Fix | D-062 in code (commit ee67c0d), Terraform tests pass |
| Verify | rebuild from nothing: reservations accepted, 134/134 |

## Investigation
- `aws ec2 describe-network-interfaces` filtered on 10.0.1.10: one
  interface, type `ec2_instance_connect_endpoint`, in use by our endpoint.
- Created instances had their fixed IPs (gw01 .0.10, idm01 .1.11, util01
  .1.12, ws-dev01 .2.10, ws-ops01 .2.11). Only control01 was missing.
- The NAT gateway had 10.0.0.169: also auto-assigned from the subnet's
  free pool, so gw01's 10.0.0.10 carried the same risk.
- Code: hosts get fixed IPs (`variables.tf` `hosts`); the endpoint
  (`access.tf`) and the NAT gateway get whatever AWS picks; nothing kept
  the hosts' addresses out of that pool, and nothing ordered the endpoint
  after control01.

## Root cause
A design gap, not an AWS fault. AWS-managed interfaces take a free private
IP chosen by AWS. Our fixed host IPs were not reserved, so whichever
resource was created first could take them. Earlier builds passed by luck
(three fixed addresses in a /24 of about 250 free ones: roughly a 1% chance
per build for the endpoint alone).

## Actions
| Action | Status |
|---|---|
| Destroy the partial lab | Done |
| Explicit subnet CIDR reservation `10.0.x.8/29` per subnet; `subnet_ids` output waits for it; NAT gateway depends on it (D-062) | Done |
| Validation: host `private_ip` must be inside its subnet's `static_cidr`; Terraform tests for both | Done |
| Rebuild from nothing with `lab.sh up`: control01 got 10.0.1.10, `lab.sh verify` 134/134 | Done |
