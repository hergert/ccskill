---
name: trigger
description: Query Trigger.dev for task run history, failures, and status; use when asked about scheduled jobs, failed runs, background tasks, or task errors.
---

# Trigger.dev Tasks

Run commands from the repo root; examples use `.codex/skills/trigger/scripts/trigger.sh`.

## Trigger phrases

Use this skill immediately when the user asks:
- "did the scheduled task run?"
- "why did the task fail?"
- "what's running right now?"
- "show me failed tasks"
- "what happened to the cron job?"
- "is the background job stuck?"
- "get the task error"

## Quick start

```bash
bash .codex/skills/trigger/scripts/trigger.sh runs              # Recent 20 runs
bash .codex/skills/trigger/scripts/trigger.sh failed 10         # Failed runs only
bash .codex/skills/trigger/scripts/trigger.sh running           # Currently executing
bash .codex/skills/trigger/scripts/trigger.sh error <run_id>    # Get error details
```

Run `bash .codex/skills/trigger/scripts/trigger.sh help` for full command list.

## Workflow: Investigating failed task

1. Run `bash .codex/skills/trigger/scripts/trigger.sh failed 10` to see recent failures
2. Note the `id` of the failed run (e.g., `run_abc123`)
3. Run `bash .codex/skills/trigger/scripts/trigger.sh error <id>` to get stack trace
4. Check the Cloud Run Logs skill for surrounding context
5. Check the Sentry skill for related issues

## Workflow: Checking task health

1. Run `bash .codex/skills/trigger/scripts/trigger.sh runs 50` to see recent history
2. Look at `status` distribution - mostly `COMPLETED`?
3. If failures, run `bash .codex/skills/trigger/scripts/trigger.sh failed` to focus on problems
4. Run `bash .codex/skills/trigger/scripts/trigger.sh tasks` to see what task types exist

## Interpreting results

| Signal | Meaning |
|--------|---------|
| `status: FAILED` | Task threw an error |
| `status: CRASHED` | Task crashed unexpectedly |
| `status: SYSTEM_FAILURE` | Infrastructure issue |
| `duration_ms` very high | Task is slow or stuck |
| Multiple failures same task | Systematic issue |

## ⚠️ Warnings

- **Run ID prefix**: Script auto-adds `run_` prefix if missing
- **Rate limits**: Don't poll too frequently
- **Logs retention**: Old run details may be unavailable

## Cross-reference

- Task errors with traces → use the Sentry skill for traces
- Errors around task time → use the Cloud Run Logs skill
- LLM calls in task → use the PostHog skill

## Configuration

Requires `TRIGGER_SECRET_KEY` in `.env`.

Script: `.codex/skills/trigger/scripts/trigger.sh`
