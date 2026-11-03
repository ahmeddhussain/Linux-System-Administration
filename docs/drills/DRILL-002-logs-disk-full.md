# DRILL-002: central log volume full (util01)

| Field | Value |
|---|---|
| Date | 2026-11-03 |
| Playbook | `ansible/playbooks/drills/logs-disk-full.yml` (`scripts/lab.sh drill logs-disk-full`) |
| Decision | D-067 |
| Result | **Finding: messages are lost while the volume is full.** Mitigation: space guard |

## Scenario
util01's `/srv/logs` (lv_logs, 6 GB) fills up. Every other host sends a
unique message; after 30 s the space is freed and the drill waits up to
five minutes for all messages.

## Runs (measured)
| Run | Setup | Stored while full | Stored after recovery | Verdict |
|---|---|---|---|---|
| 1 | volume filled to "100%" but 2 MB left free | 5/5 | 5/5 | **invalid drill**: the messages fitted in the 2 MB |
| 2 | filled until writes are refused | 4/5 | 4/5 (310 s) | 1 message lost |
| 3 | as 2, with retrying action queues on util01 | 2/5 | 2/5 (310 s) | 3 messages lost: the fix did not work |

Messages that "survived" a full disk went to files that already existed
and had room left in their last allocated block.

## Investigation
- The senders' disk queues (D-059) hold messages only while util01 does
  not accept them. util01 accepts each message over TCP first and writes
  it afterwards, so a failed write is util01's problem alone.
- util01's journal during run 3: `file '/srv/logs/.../audit.log' write
  error ... No space left on device` followed by `action ... message lost,
  could not be processed`. rsyslog's file output treats a full disk as a
  permanent error for that message: it is not suspended or retried, so
  queues and `action.resumeRetryCount` cannot help (the hypothesis behind
  run 3, disproved; change reverted).

## Root cause
Losing messages on a full log disk is rsyslog's designed behaviour. The
defence is to keep the volume from filling.

## Actions
| Action | Status |
|---|---|
| Drill fills until writes are refused (run 1 was invalid) | Done |
| Space guard on util01 (`ahmed-logspace`, every 5 min): above 85% deletes the oldest rotated logs (older copies are in the S3 backups) until below 80%; warns, and errors when nothing is left to delete | Done |
| Test: the guard timer is active and its check runs | Done |
| The drill keeps showing the hard limit (an instant fill cannot be prevented); a slow fill, the realistic case, is caught by the guard | Accepted |
| Option for later: alert to an admin from the guard's error (no alerting system in the lab yet) | Open |
