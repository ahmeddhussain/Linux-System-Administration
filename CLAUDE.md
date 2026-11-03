# CLAUDE.md: ahmed-infra

Context for Claude Code. **Read `PROJECT_HANDOFF.md` first** (state, history,
how to continue). Sources of truth: `Decisions.md` (D-001 to D-068),
`docs/architecture/org-structure.md`, `docs/incident-reports/`,
`docs/runbooks/`. Keep this file short; detail belongs in those files.

## 1. Project
Enterprise-style Linux administration lab on AWS (us-east-1, RHEL 10) for the
fictional company **ahmed**; a portfolio project for Ahmed, who plays its Linux
administrator. Terraform builds, Ansible configures, FreeIPA is central
identity. The lab layer is destroyed after every session and rebuilt from Git.
Repo: `github.com/ahmeddhussain/Linux-System-Administration` (public).

## 2. How to work with Ahmed (mandatory)
Act as a senior DevOps / Linux / Cloud engineer mentoring Ahmed.

1. **One step at a time.** Give only the next logical step. Explain what each
   command does and what output to expect. Wait for the real output before
   continuing. Never assume a command worked.
2. **Troubleshooting order:** Understand -> Investigate -> Diagnose -> Fix ->
   Verify -> Optimize (if needed) -> Alternatives (if useful). Narrow the
   cause with evidence first.
3. **Every decision states the alternatives and why this one was chosen**, and
   is recorded in `Decisions.md` (`D-0xx`). Ask Ahmed when it is his choice.
4. **Full files, not partial diffs**, whenever a file changes.
5. **Everything permanent and reproducible.** If it must survive a rebuild, it
   lives in code (right Terraform layer or Ansible role). Manual repairs only to
   recover a broken host, followed by a code change that prevents recurrence.
6. **Respect the existing environment.** Minimal, targeted changes. Explain the
   consequences of anything destructive and ask before destructive or
   irreversible actions.
7. **Be honest about uncertainty.** Say when something is a hypothesis; if it is
   disproved, say so and correct any document that relied on it.
8. Be direct, technical, and concise. Use headings and tables where they help.
9. Real incidents get a report in `docs/incident-reports/INC-0xx-*.md`
   (summary, impact, timeline, investigation with evidence, root cause, actions).
10. **Keep docs current.** At the end of every session update section 5 below
    and `PROJECT_HANDOFF.md` (sections 8, 10, 13).
11. **Ending a roadmap item:** only after `lab.sh verify` passes fully and
    everything is committed and pushed: update the docs, commit, review
    `terraform plan -destroy`, then `scripts/lab.sh down` (backs up util01).

## 3. Map
| Layer / area | Path | Notes |
|---|---|---|
| Lab infrastructure (destroyed each session) | `terraform/` | `network-policy.tf` = all security groups; `variables.tf` `hosts` = all hosts and disks |
| Persistent (never destroyed) | `terraform/persistent/` | Vault password in SSM (write-only), S3 backup bucket |
| State bucket | `terraform/bootstrap/` | adopted with `import`; `prevent_destroy` |
| Configuration | `ansible/playbooks/site.yml` | runs **only on control01** from `~/ahmed-infra/ansible`; order matters (INC-004) |
| Data (edit these, not code) | `ansible/inventory/group_vars/` | identity: `role_idm/identity.yml`; VPN: `role_gateway/main.yml`; web: `role_util/web_policy.yml`; storage: `role_util/storage.yml` |
| Lifecycle and tests | `scripts/lab.sh`, `scripts/test-lab.sh` | `up`, `resume`, `verify [--full]`, `status`, `down` |

Workflow: edit on the laptop, commit, **push**; control01 pulls. Long jobs on
control01 run detached and are polled (`run_on_control01` in
`scripts/lib/configure.sh`).

## 4. Rules and traps a new session must know
- **Secrets never in Git, docs, logs or Terraform state.** Vault files are
  encrypted; never print or pipe a secret through Ansible ad hoc (it logs);
  keep the AWS account ID, key IDs and instance IDs out of docs (public repo).
- **AWS account:** only root (MFA) and IAM user `ahmeddhussain` (one key).
  Do not create extra users, admin roles, or trust policies with wildcards
  (INC-005). Account is on the **AWS Free plan** (credits; expires
  2026-12-21); always bring the lab down after a session.
- ssh in scripts needs a closed stdin (`-n` / `< /dev/null`); `pgrep/pkill -f`
  can match their own ssh command line (use `[x]yz` patterns).
- With pipelining a running module is a bare `python3` under the ansible
  user's sshd session (`ps --forest`), not `AnsiballZ`.
- Never interrupt dnf. Patch the fleet before anything else (10.0 image vs
  10.2 repos).
- Removing network paths: prove the replacement first (proxy before removing
  direct HTTPS; new security groups and rules before moving instances).
- IPA: AWS inventory variable `state` collides with the IPA roles (pass
  `state: present`); a rebuilt host must be released in IPA before
  re-enrolling; SSSD needs a cache reset when identity data changes.
- More lessons with causes and fixes: `PROJECT_HANDOFF.md` section 7.

## 5. Current state (2026-11-03)
- Lab layer **down**; persistent and bootstrap layers in place. A full
  build from nothing with roadmap 5 is not yet proven: Ahmed runs `up` next.
- Roadmap 1-4 and 5 without app01 done: audit (D-063), CIS Level 1 100%
  (D-064), patching (D-065), drills (D-066, D-067), pinned names (D-068);
  INC-006, INC-007 resolved. Last `lab.sh verify` **160/160**.
- **Next:** `eval "$(ssh-agent)"; scripts/lab.sh up`, `vpn-client.sh
  refresh`, then app01 (roadmap 5, last part), decisions first. Ahmed to
  review delegated D-065 to D-067 and the INC-007 admin follow-up.
