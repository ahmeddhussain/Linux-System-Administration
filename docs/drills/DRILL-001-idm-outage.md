# DRILL-001: identity server outage (idm01)

| Field | Value |
|---|---|
| Date | 2026-11-03 |
| Playbook | `ansible/playbooks/drills/idm-outage.yml` (`scripts/lab.sh drill idm-outage`) |
| Decision | D-067 |
| Result | Recovery OK; finding (IPA's DNS a single point of failure) fixed by D-068 and verified by a rerun |

## Scenario
All IPA services on idm01 stopped (`ipactl stop`): LDAP, Kerberos, DNS, CA,
web UI. Observed on every IPA client except gw01, then IPA started again
and the time measured until each client's SSSD was online again, without
any help (no SSSD restart).

## Result (measured)
| Client | Known user resolves (SSSD cache) | Company names resolve (DNS) | SSSD state | Online again after restart |
|---|---|---|---|---|
| control01 | yes | **no** | offline | 52 s |
| util01 | yes | yes (own name, see below) | offline | 52 s |
| ws-dev01 | yes | **no** | offline | 52 s |
| ws-ops01 | yes | **no** | offline | 52 s |

IPA was down 33 s. Result line in `/srv/logs/reports/drills/incident-drills.log`.

## What worked
- SSSD's cache: identities kept resolving on every client while IPA was
  down, so files, running sessions and cached logins keep working.
- Recovery needs nothing: SSSD went back online by itself within a minute.

## Finding: DNS
All hosts use idm01 (10.0.1.11) as their first nameserver; the second, the
VPC resolver, does not know `ahmed.internal`. With IPA down, company names
do not resolve, so:
- workstations cannot reach the proxy (`util01.ahmed.internal`), so no web
  and no dnf;
- new NFS automounts fail (homes already mounted keep working);
- log forwarding cannot reconnect to `util01.ahmed.internal` (the disk
  queues keep the messages, D-059);
- Kerberos and IPA enrollment stop (expected with IPA down).

util01's lookup succeeded only because it looked up its own name, which
glibc's `nss-myhostname` answers locally; it is not a DNS success.

## Options (Ahmed chose B, D-068; A stays roadmap item 6)
| Option | Effect | Cost |
|---|---|---|
| A. A second IPA server (replica) with DNS (roadmap item 6) | Identity and DNS survive one server; the real fix | one more c7i-flex.large-class host |
| B. Pin the infrastructure names in `/etc/hosts` from Ansible (util01, idm01; fixed IPs, D-062) | Proxy, NFS and logs survive a DNS outage | a second source of truth for a few names |
| C. Route 53 private zone as a fallback resolver | Names resolve from AWS | a second DNS to keep in sync with IPA |

Recommendation: B now (small, uses the fixed IPs that D-062 already
guarantees), A when roadmap item 6 adds a replica.

## Rerun after D-068 (2026-11-03 19:29 UTC)
| Client | Known user resolves | Company names resolve | SSSD | Online again after restart |
|---|---|---|---|---|
| control01, util01, ws-dev01, ws-ops01 | yes | **yes** (pinned names) | offline | 63 s |

With IPA down, the proxy, NFS and log server names now resolve on every
client. Identity itself (new logins of users not in the cache, Kerberos,
sudo rule updates) still needs idm01: the replica of roadmap item 6.
