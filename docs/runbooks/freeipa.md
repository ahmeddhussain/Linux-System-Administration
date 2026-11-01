# FreeIPA (idm01): operating runbook

Design: `docs/architecture/freeipa-options.md`, decisions D-046 to D-051.
Everything is code (D-048): never change IPA by hand. Change the files
below and rerun the playbook.

## Where things live
| What | File |
|---|---|
| Server settings (realm, DNS, reverse zones, no allow_all) | `ansible/inventory/group_vars/role_idm/main.yml` |
| Admin and Directory Manager passwords | `ansible/inventory/group_vars/role_idm/vault.yml` (encrypted) |
| Users, groups, host groups, HBAC, sudo rules | `ansible/inventory/group_vars/role_idm/identity.yml` |
| Client settings (DNS resolver, SSHFP) | `ansible/inventory/group_vars/ipaclients.yml` |
| Private test keys for the users | `ansible/tests/test-user-keys.vault.yml` (encrypted) |
| Playbook | `ansible/playbooks/idm.yml` (imported by `site.yml`) |

## Apply a change
On control01, from `~/ahmed-infra/ansible`, after `git pull`:

    ansible-playbook playbooks/idm.yml

Order: server, clients two at a time, control01 last, identity data, then
an SSSD cache reset on clients whose copy of the identity data changed.
A rerun with no changes reports `changed=0`.

## Common tasks
- **Add a user:** add an entry to `ipa_users` in `identity.yml` with a
  team in `groups` and an SSH public key, then run the playbook.
- **Add a team:** add it to `ipa_groups`, plus HBAC and sudo rules, and
  follow the checklist in `org-structure.md`.
- **Look at a password** (control01 only): `ansible-vault view
  inventory/group_vars/role_idm/vault.yml`. Never paste it anywhere.

## Checks (all of these are also in `scripts/test-lab.sh`)
On idm01 as root:

    ipactl status                                  # every service RUNNING
    export KRB5CCNAME=$(mktemp -u); kinit -k       # host ticket, no password
    ipa sudorule-show ops-all; ipa hbacrule-find   # rules as in identity.yml
    kdestroy

On any client:

    id sara                                        # SSSD resolves IPA users
    sudo -l -U sara                                # sudo rules SSSD applies
    dig +short gw01.ahmed.internal                 # IPA DNS answers

## Troubleshooting (seen while building, 2026-11-01)
| Symptom | Cause | Fix in code |
|---|---|---|
| Install and uninstall tasks both skipped | AWS inventory defines a host variable `state` | `state: present` on every role call |
| Client: "no certificate or crl found", empty `/etc/ipa/ca.crt` | Server given by short name; IPA's web server redirects it | `ipaclient_servers` uses the full name |
| Client: "Failed to verify that ... is an IPA Server" on retry | Empty `ca.crt` left by the failed attempt | pre-task removes an empty `ca.crt` on unenrolled hosts |
| OTP step UNREACHABLE on `idm01.ahmed.internal` | Role delegates to a DNS name that is not an inventory host | play creates the OTP via `idm01` |
| control01: "No module named 'ipapython'" | local modules ran in the venv | `role_control.yml`: system Python |
| `sudo -l -U <user>` says not allowed, although the rule is right in IPA | SSSD kept an empty sudo cache from before the rule existed | checksum play resets the cache |

To check the last case by hand on a client: `sudo -l -U <user>`. If the rule
is missing, the cache reset is the fix (stop sssd, remove
`/var/lib/sss/db/cache_*` and `timestamps_*`, start sssd). Make the fix
permanent by rerunning the playbook, not by hand.
