---
name: trigger
description: Query Trigger.dev for task run history and failures. Use when user asks about scheduled tasks, failed jobs, background task status, or task errors.
---

# Trigger.dev Tasks

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
trigger.sh runs              # Recent 20 runs
trigger.sh failed 10         # Failed runs only
trigger.sh running           # Currently executing
trigger.sh error <run_id>    # Get error details
```

Run `trigger.sh help` for full command list.

## Workflow: Investigating failed task

1. Run `trigger.sh failed 10` to see recent failures
2. Note the `id` of the failed run (e.g., `run_abc123`)
3. Run `trigger.sh error <id>` to get stack trace
4. Check `/cloudrun-logs since` for surrounding context
5. Check `/sentry errors` for related issues

## Workflow: Checking task health

1. Run `trigger.sh runs 50` to see recent history
2. Look at `status` distribution - mostly `COMPLETED`?
3. If failures, run `trigger.sh failed` to focus on problems
4. Run `trigger.sh tasks` to see what task types exist

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

- Task errors with traces → `/sentry trace <id>`
- Errors around task time → `/cloudrun-logs since`
- LLM calls in task → `/posthog llm`

## Configuration

Requires `TRIGGER_SECRET_KEY` in `.env`.

Script: `.claude/skills/trigger/scripts/trigger.sh`
