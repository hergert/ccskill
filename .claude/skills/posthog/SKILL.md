---
name: posthog
description: Query PostHog for LLM observability and pipeline health. Use when user asks about LLM costs, token usage, latency, slow AI calls, or pipeline step failures.
---

# PostHog Analytics

## Trigger phrases

Use this skill immediately when the user asks:
- "how much did LLM cost today?"
- "why are tokens so high?"
- "what's our AI spend?"
- "which LLM calls are slow?"
- "is the pipeline healthy?"
- "why is the pipeline failing?"
- "are dashboards broken?"

## Quick start

```bash
posthog.sh llm 1          # LLM summary for last hour
posthog.sh llm-slow 1 10  # Top 10 slowest calls
posthog.sh pipeline 24    # Pipeline health last 24h
posthog.sh triage         # Scan for broken insights
```

Run `posthog.sh help` for full command list.

## Workflow: Debugging slow LLM calls

1. Run `posthog.sh llm 1` to see if latency is high
2. If `latency_sec.avg` > 5s, run `posthog.sh llm-slow 1 10`
3. Note `span_name` and `story_id` from slow calls
4. Cross-reference with `/sentry spans` for traces

## Workflow: Debugging broken dashboard

1. Run `posthog.sh triage` to find issues
2. If `not_saved` insights found, run `posthog.sh triage-fix`
3. If `wrong_wrapper` found, run `posthog.sh insight <id>` to inspect
4. Check `query.kind` - should be `InsightVizNode` or `DataTableNode`

## Interpreting results

| Signal | Meaning |
|--------|---------|
| `cost_usd` > $0.10/hour on low traffic | Investigate model choice |
| `latency_sec.avg` > 5s | Check llm-slow output |
| `tokens.input` >> `tokens.output` | Prompts too long |
| `success_pct` < 90 | Pipeline step failing |

## ⚠️ Warnings

- **API key type matters**: Need personal key (`phx_*`), not project key (`phc_*`)
- **Rate limits**: Don't hammer the API - cache results when iterating
- **Event lag**: PostHog events can be delayed 1-2 minutes

## Cross-reference

- Slow LLM spans → `/sentry spans` for trace details
- Pipeline failures → `/trigger failed` for task errors
- Errors after pipeline run → `/cloudrun-logs since`

## Configuration

Requires `POSTHOG_PERSONAL_API_KEY` in `.env`. Get one at https://us.posthog.com/settings/user-api-keys

Script: `.claude/skills/posthog/scripts/posthog.sh`
