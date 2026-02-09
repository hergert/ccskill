---
name: posthog
description: Query PostHog for LLM observability (cost, tokens, latency) and pipeline health; use when asked about LLM spend, token usage, slow calls, or pipeline failures.
---

# PostHog Analytics

Run commands from the repo root; examples use `.codex/skills/posthog/scripts/posthog.sh`.

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
bash .codex/skills/posthog/scripts/posthog.sh llm 1          # LLM summary for last hour
bash .codex/skills/posthog/scripts/posthog.sh llm-slow 1 10  # Top 10 slowest calls
bash .codex/skills/posthog/scripts/posthog.sh pipeline 24    # Pipeline health last 24h
bash .codex/skills/posthog/scripts/posthog.sh triage         # Scan for broken insights
```

Run `bash .codex/skills/posthog/scripts/posthog.sh help` for full command list.

## Workflow: Debugging slow LLM calls

1. Run `bash .codex/skills/posthog/scripts/posthog.sh llm 1` to see if latency is high
2. If `latency_sec.avg` > 5s, run `bash .codex/skills/posthog/scripts/posthog.sh llm-slow 1 10`
3. Note `span_name` and `story_id` from slow calls
4. Cross-reference with the Sentry skill for traces

## Workflow: Debugging broken dashboard

1. Run `bash .codex/skills/posthog/scripts/posthog.sh triage` to find issues
2. If `not_saved` insights found, run `bash .codex/skills/posthog/scripts/posthog.sh triage-fix`
3. If `wrong_wrapper` found, run `bash .codex/skills/posthog/scripts/posthog.sh insight <id>` to inspect
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

- Slow LLM spans → use the Sentry skill for trace details
- Pipeline failures → use the Trigger skill for task errors
- Errors after pipeline run → use the Cloud Run Logs skill

## Configuration

Add to `.env`:

```
POSTHOG_PERSONAL_API_KEY=phx_...
POSTHOG_PROJECT_ID=12345
```

Get a personal API key at https://us.posthog.com/settings/user-api-keys

Script: `.codex/skills/posthog/scripts/posthog.sh`
