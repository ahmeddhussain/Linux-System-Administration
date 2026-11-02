# INC-005: leaked IAM access key used for Amazon Bedrock

| Field | Value |
|---|---|
| Date | 2026-11-02 |
| Severity | High (the leaked key had AdministratorAccess); actual damage small |
| Status | Contained and closed |
| Scope | AWS account; not the lab (the lab's own credentials were not involved) |

## Summary
AWS Marketplace emailed that the account had accepted an agreement for an
Anthropic model on Amazon Bedrock. Nobody working on the lab had done
that. CloudTrail showed a second IAM user's long-term access key being
used from an unknown machine to grant itself Bedrock access, accept model
agreements and call models. The key had administrator rights. It was
blocked within minutes of the investigation starting; the account was then
reduced to the root user and one IAM user with a new key.

## Impact
- 10 model calls, 11 model agreements and 1 model-access request, in one
  region (us-east-1), over about seven minutes. **Cost: none.** All 10
  calls were rejected by Bedrock (ThrottlingException: the account has no
  capacity for that model); CloudWatch shows throttles and no token usage,
  and agreements themselves are free. The account is on the AWS Free plan,
  so usage would have drawn on credits rather than a card in any case.
- No other activity by the attacker: no servers, functions or other
  resources in any region, and no new users, keys or console logins
  (backdoors) in the 90 days of CloudTrail history.

## Timeline (UTC)
| Time | Event |
|---|---|
| 2026-08-16 | Two extra IAM users created by the account owner, each with an access key, console password, no MFA, AdministratorAccess |
| 16:10 | The leaked key attaches a Bedrock full-access policy to its own user |
| 16:10-16:17 | Model-access request, agreements accepted, model calls |
| ~16:15 | Marketplace email reported; investigation starts |
| 16:20 | Key deactivated; explicit deny-all on both extra users |
| 16:30 | Lab user's key rotated (new key, old one deleted) |
| 16:32 | Both extra users deleted |
| later | Owner deletes two GitHub Actions roles, two orphaned EKS roles, an unused RDS role, the GitHub OIDC provider and the admin group; cancels the Marketplace subscriptions; budget alert in place |

## Investigation
- CloudTrail event history by event source (Bedrock, Marketplace) found
  the activity; filtering by user name showed one key, one source address,
  and a different machine from the lab's.
- The lab user's key had been used only from the owner's address.
- The repository's whole Git history contains no AWS keys: the key did
  not leak from this project.
- Found while checking for backdoors: two GitHub Actions roles with
  AdministratorAccess whose trust policy allowed `repo:*`, i.e. any
  repository on GitHub could assume them. Not used in this incident, but an
  open door; deleted.

## Root cause
A long-term access key of a second IAM user with AdministratorAccess leaked
outside this project (where exactly is unknown). Contributing: no MFA on
the IAM users, administrator rights for everyone, keys never rotated, and
no alerting on unusual activity.

## Actions
| Action | Status |
|---|---|
| Deactivate the leaked key, deny-all on the users, delete them | Done |
| Check every region for resources and CloudTrail for backdoors and model use | Done: none beyond the above |
| Rotate the remaining user's key | Done |
| Delete roles open to any GitHub repository and other unused roles | Done |
| Cancel Marketplace subscriptions; budget alert | Done (owner) |
| MFA and a new console password for the remaining IAM user | Owner |
| Keep long-term keys to one user; prefer short-lived credentials | Ongoing |

## Lessons
- Read the order of fields in CLI text output: `--output text` printed the
  account summary in alphabetical order, which was first misread as "root
  has an access key and no MFA" (it had MFA and no keys).
- CloudTrail event history lags by minutes; "not visible yet" is not "did
  not happen".
- Every principal with AdministratorAccess is the whole account. Fewer
  admins, MFA everywhere, and trust policies that name exact repositories.
