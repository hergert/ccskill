---
name: sentry
description: Query Sentry for errors, performance traces, and slow spans. Use when user asks about production errors, slow endpoints, error rates, or wants to analyze a trace.
---

# Sentry Stats

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
sentry-stats.sh errors           # Unresolved errors
sentry-stats.sh perf 24h         # Endpoint p95 latency
sentry-stats.sh spans /api 7d    # Slow spans for /api
sentry-stats.sh trace <id>       # Analyze a trace
```

Run `sentry-stats.sh help` for full command list.

## Workflow: Debugging slow endpoint

1. Run `sentry-stats.sh perf 24h` to see p95 by endpoint
2. Identify slow endpoint, run `sentry-stats.sh spans /endpoint 7d`
3. Get `trace_id` from slowest span
4. Run `sentry-stats.sh trace <trace_id>` to see breakdown
5. Look at `by_operation` - that's where time is spent

## Workflow: Investigating errors

1. Run `sentry-stats.sh errors` to see unresolved issues
2. Note `shortId` (e.g., `SCRIBE-123`)
3. Run `sentry-stats.sh issue <id>` for details
4. Run `sentry-stats.sh events <id>` for recent occurrences
5. Check `/cloudrun-logs since` for surrounding context

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

- Slow LLM spans found → `/posthog llm-slow` for LLM details
- Errors after deploy → `/cloudrun-logs since` for context
- Task failures in traces → `/trigger failed` for task errors

## Configuration

Requires `SENTRY_AUTH_TOKEN` in `.env`. Get one at https://sentry.io/settings/auth-tokens/

Script: `.claude/skills/sentry/scripts/sentry-stats.sh`
