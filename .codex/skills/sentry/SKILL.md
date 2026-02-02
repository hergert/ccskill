---
name: sentry
description: Query Sentry for production errors, performance traces, spans, and latency metrics; use when asked about errors, error rates, slow endpoints, or trace analysis.
---

# Sentry Stats

Run commands from the repo root; examples use `.codex/skills/sentry/scripts/sentry-stats.sh`.

## Trigger phrases

Use this skill immediately when the user asks:
- "are there any errors in production?"
- "what's breaking?"
- "why is this endpoint slow?"
- "show me the trace"
- "what's the p95 latency?"
- "any new errors today?"
- "debug this error"

## Quick start

```bash
bash .codex/skills/sentry/scripts/sentry-stats.sh errors           # Unresolved errors
bash .codex/skills/sentry/scripts/sentry-stats.sh perf 24h         # Endpoint p95 latency
bash .codex/skills/sentry/scripts/sentry-stats.sh spans /api 7d    # Slow spans for /api
bash .codex/skills/sentry/scripts/sentry-stats.sh trace <id>       # Analyze a trace
```

Run `bash .codex/skills/sentry/scripts/sentry-stats.sh help` for full command list.

## Workflow: Debugging slow endpoint

1. Run `bash .codex/skills/sentry/scripts/sentry-stats.sh perf 24h` to see p95 by endpoint
2. Identify slow endpoint, run `bash .codex/skills/sentry/scripts/sentry-stats.sh spans /endpoint 7d`
3. Get `trace_id` from slowest span
4. Run `bash .codex/skills/sentry/scripts/sentry-stats.sh trace <trace_id>` to see breakdown
5. Look at `by_operation` - that's where time is spent

## Workflow: Investigating errors

1. Run `bash .codex/skills/sentry/scripts/sentry-stats.sh errors` to see unresolved issues
2. Note `shortId` (e.g., `SCRIBE-123`)
3. Run `bash .codex/skills/sentry/scripts/sentry-stats.sh issue <id>` for details
4. Run `bash .codex/skills/sentry/scripts/sentry-stats.sh events <id>` for recent occurrences
5. Check the Cloud Run Logs skill for surrounding context

## Interpreting results

| Signal | Meaning |
|--------|---------|
| `p95_ms` > 5000 | Endpoint needs optimization |
| `count` increasing | Error is recurring |
| `userCount` high | Widespread impact |
| `by_operation` shows one slow op | Found the culprit |

## ⚠️ Warnings

- **Trace retention**: Traces older than 14 days may be unavailable
- **Span sampling**: Not all requests are traced - you see a sample
- **Middleware noise**: `spans` excludes middleware by default

## Cross-reference

- Slow LLM spans found → use the PostHog skill for LLM details
- Errors after deploy → use the Cloud Run Logs skill for context
- Task failures in traces → use the Trigger skill for task errors

## Configuration

Requires `SENTRY_AUTH_TOKEN` in `.env`. Get one at https://sentry.io/settings/auth-tokens/

Script: `.codex/skills/sentry/scripts/sentry-stats.sh`
