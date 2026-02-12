---
name: posthog
description: Query PostHog analytics — events, dashboards, insights, and LLM observability. Use when user asks about event data, dashboard health, insight debugging, or LLM costs and latency.
---

# PostHog Analytics

## Trigger phrases

Use this skill when the user asks:
- "what events are we tracking?"
- "show me dashboard status"
- "why is this insight empty?"
- "how much did LLM cost today?"
- "which LLM calls are slow?"
- "are dashboards broken?"

## Commands

### Explore events

| Command | What it does |
|---------|-------------|
| `posthog.sh events [hours]` | Event distribution — see all tracked events and counts (default: 24h) |
| `posthog.sh trends <event> [breakdown] [hours]` | Trend line for any event, optional breakdown by property (default: 24h) |
| `posthog.sh raw <event> [limit] [hours]` | Raw event data with all properties (default: 20 events, 24h) |

**Start here.** Run `events` first to see what's available, then drill into specific events with `trends` or `raw`.

### Dashboards

| Command | What it does |
|---------|-------------|
| `posthog.sh dashboards` | List all dashboards with URLs |
| `posthog.sh dashboard <name>` | Find dashboard by name (partial match), show its insights |
| `posthog.sh dashboard-detail <id\|name>` | Full dashboard: tiles, insight configs, filters, refresh status |

### Insights (debugging empty or broken insights)

| Command | What it does |
|---------|-------------|
| `posthog.sh insight <id>` | Get insight config: query, filters, saved status, warnings |
| `posthog.sh insight-test <id>` | Execute the insight's query and check if it returns data |
| `posthog.sh insight-refresh <id>` | Force cache refresh |
| `posthog.sh insight-save <id>` | Set `saved=true` (required for dashboard rendering) |
| `posthog.sh insight-delete <id>` | Delete an insight |
| `posthog.sh triage` | Scan all insights for issues: `not_saved`, `wrong_wrapper` |
| `posthog.sh triage-fix` | Auto-fix all `not_saved` insights |

### LLM analytics (requires $ai_generation events)

These commands only work if your project sends PostHog's standard `$ai_generation` events (e.g., via LangChain, Vercel AI SDK, or custom instrumentation).

| Command | What it does |
|---------|-------------|
| `posthog.sh llm [hours]` | Summary: call count, latency stats, token counts, cost (default: 1h) |
| `posthog.sh llm-slow [hours] [n]` | Top N slowest LLM calls with model, tokens, custom properties (default: 1h, 10) |
| `posthog.sh llm-by-type [hours]` | Breakdown by `span_name`: calls, latency, cost per type (default: 1h) |

## Workflow: Exploring your data

1. Run `posthog.sh events 24` — see all event types and counts
2. Pick an event name from the output
3. Run `posthog.sh trends <event_name> 24` — see the trend over time
4. For property-level detail: `posthog.sh raw <event_name> 5` — inspect actual event payloads
5. To break down by a property: `posthog.sh trends <event> <property> 24`

## Workflow: Debugging empty/broken dashboard

1. Run `posthog.sh triage` — scans all insights for known issues
2. Check `summary`: `not_saved_count` and `wrong_wrapper_count`
3. If `not_saved` insights found → run `posthog.sh triage-fix` to auto-fix
4. If `wrong_wrapper` found → run `posthog.sh insight <id>` and check `query_kind`
   - Should be `InsightVizNode` or `DataTableNode`
5. To verify an insight returns data: `posthog.sh insight-test <id>`

## Workflow: Debugging slow LLM calls

1. Run `posthog.sh llm 1` — check if `latency_sec.avg` > 5s
2. If slow: `posthog.sh llm-slow 1 10` — see the slowest calls
3. Note `span_name` and `model` from slow calls
4. Run `posthog.sh llm-by-type 1` — see which call types cost the most

## Interpreting results

| Key | What it means |
|-----|--------------|
| `cost_usd` > $0.10/hour on low traffic | Model may be too expensive for the task |
| `latency_sec.avg` > 5s | LLM calls are slow — check `llm-slow` |
| `tokens.input` >> `tokens.output` | Prompts may be too long |
| `has_data: false` on `insight-test` | Insight query returns nothing — check filters/date range |
| `not_saved_count` > 0 on `triage` | Insights won't render on dashboards until saved |

## Warnings

- **API key type matters**: Need personal key (`phx_*`), not project key (`phc_*`)
- **Rate limits**: Don't hammer the API — cache results when iterating
- **Event lag**: PostHog events can be delayed 1-2 minutes
- **`insight-test` timeout**: Large queries may take >30s — increase date range if no data

## Configuration

Add to `.env`:

```
POSTHOG_PERSONAL_API_KEY=phx_...
POSTHOG_PROJECT_ID=12345
```

Get a personal API key at https://us.posthog.com/settings/user-api-keys

Script: `.claude/skills/posthog/scripts/posthog.sh`
