# INC-007: SSH offered keyboard-interactive (password) logins on every host

| Field | Value |
|---|---|
| Date | 2026-11-03 |
| Severity | High: password logins possible for IPA's `admin` (full sudo) on every host; no evidence of use |
| Status | Resolved (commit 75f0dc9; test added) |
| Systems | All six hosts (sshd) |

## Summary
While fixing the CIS Level 1 SSH findings (D-064), the effective sshd
configuration (`sshd -T`) showed `kbdinteractiveauthentication yes` and
`gssapiauthentication yes` on every host, although our drop-in set both to
`no`. Every server offered `keyboard-interactive`, which is PAM password
authentication, next to public keys. The design (D-058, D-057) assumes
logins are key-only.

## Impact
- Any account with a password could have logged in over SSH with it,
  limited by HBAC (who may log in where) and the network policy (who can
  reach port 22). Employees and test users log in with keys.
- IPA's own `admin` account has a password (vault) and is a member of IPA's
  built-in `admins` group, which the `admins-everywhere` HBAC rule and the
  `admins-all` sudo rule use. So `admin` could have logged in with its
  password on every host reachable on port 22 (from control01 and the admin
  VPN range), with full sudo. Not tested with the password (it is not read
  outside Ansible); the server offered the method and HBAC allowed the user.
- No evidence of password logins: tests and admins use keys. Not proven
  either way for the past; the lab is rebuilt every session and journal
  history was not kept between sessions.

## Timeline (2026-11-03)
| Step | Event |
|---|---|
| CIS scan (5b) | `sshd_disable_gssapi_auth` fails on workstations |
| Investigation | `/etc/ssh/sshd_config.d/` lists `04-ipa.conf` before `10-ahmed-hardening.conf`; `sshd -T` on all hosts: `kbdinteractiveauthentication yes` |
| Confirmation | an SSH probe from control01 without a key: `Permission denied (publickey,gssapi-keyex,gssapi-with-mic,keyboard-interactive)` |
| Fix | drop-in renamed to `01-ahmed-hardening.conf`, explicit `KbdInteractiveAuthentication no` and `GSSAPIAuthentication no` |
| Verification | probe offers `(publickey)` only; new test |

## Investigation
- sshd keeps the **first** value it reads for each keyword; drop-ins are read
  in name order, before the rest of `sshd_config`.
- The IPA client writes `04-ipa.conf` with `ChallengeResponseAuthentication
  yes` (an old alias of `KbdInteractiveAuthentication`) and
  `GSSAPIAuthentication yes`. It sorts before our `10-` file, so it won.
- `PasswordAuthentication no` held (IPA does not set it), which is why the
  existing test, which tries only the `password` method, passed.

## Root cause
Our drop-in assumed "the later file wins", the opposite of how sshd treats
repeated keywords, and the test checked one authentication method instead
of what the server actually offers.

## Actions
| Action | Status |
|---|---|
| Drop-in renamed `01-ahmed-hardening.conf` (read first); old file removed | Done |
| Explicit `KbdInteractiveAuthentication no`, `GSSAPIAuthentication no`, plus the CIS Level 1 SSH settings | Done |
| Test: every server offers `publickey` and nothing else | Done |
| Test: effective `sshd -T` values include kbdinteractive and gssapi `no` | Done |
| Lesson in PROJECT_HANDOFF.md section 7 | Done |
| Follow-up: IPA's `admin` is a break-glass identity, not a daily login; consider a separate HBAC group for named admins so `admin` cannot log into hosts at all | Open (proposed, needs Ahmed's decision) |
