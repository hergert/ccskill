---
name: cloudrun-logs
description: Query Google Cloud Run logs for debugging deployments and errors. Use after deploying, when checking for crashes, or investigating production issues.
---

# Cloud Run Logs

## Trigger phrases

Use this skill immediately when the user asks:
- "did the deploy break anything?"
- "check logs after deploy"
- "any errors in production?"
- "is the service healthy?"
- "what's in the logs?"
- "tail the logs"
- "why did the service crash?"

## Quick start

```bash
cloudrun-logs.sh since    # Logs since last deploy ← START HERE
cloudrun-logs.sh errors   # Filter for errors only
cloudrun-logs.sh tail 30  # Live tail for 30 seconds
cloudrun-logs.sh status   # Service health check
```

Run `cloudrun-logs.sh help` for full command list.

## Workflow: Post-deploy verification

**Always run `since` after deploying:**

1. Run `cloudrun-logs.sh since` immediately after deploy
2. Scan for errors, exceptions, crashes
3. If errors found, run `cloudrun-logs.sh errors` to filter
4. Cross-reference with `/sentry errors` for stack traces
5. If task failures, check `/trigger failed`

## Workflow: Live debugging

1. Run `cloudrun-logs.sh tail 60` to watch logs
2. Trigger the problematic action
3. Look for errors in real-time
4. Stop with Ctrl+C when you've seen enough

## Interpreting results

| Pattern | Meaning |
|---------|---------|
| `error`, `exception`, `fatal` | Something broke |
| `timeout` | Request too slow |
| `denied`, `refused` | Permission/auth issue |
| `crash`, `panic` | Service crashed |
| No logs after deploy | Service didn't start |

## ⚠️ Warnings

- **First-time setup required**: Run `cloudrun-logs.sh init` to configure
- **gcloud auth**: Must be authenticated with correct account
- **Log delay**: Logs can be delayed 10-30 seconds
- **gcloud crashes**: Script has fallback to logging API if `gcloud run logs` crashes

## Cross-reference

- Errors found → `/sentry errors` for stack traces
- Task failures in logs → `/trigger failed` for details
- LLM errors → `/posthog llm` for call details

## First-time setup

```bash
cloudrun-logs.sh init  # Interactive setup
```

Saves config to `.cloudrun-logs` file.

## Configuration

Requires `gcloud` CLI authenticated.

Script: `.claude/skills/cloudrun-logs/scripts/cloudrun-logs.sh`
