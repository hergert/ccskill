#!/bin/bash
# posthog.sh - Query PostHog analytics (agent-friendly)
# All output is JSON to stdout. No stderr noise.
#
# Explore:
#   posthog.sh events [hours]           # Event distribution
#   posthog.sh trends <event> [brk] [h] # Trends with optional breakdown
#   posthog.sh raw <event> [n] [h]      # Raw events
#
# Dashboards:
#   posthog.sh dashboards               # List all dashboards
#   posthog.sh dashboard <name>         # Get dashboard by name
#   posthog.sh dashboard-detail <id>    # Full dashboard with tile configs
#
# Insights:
#   posthog.sh insight <id>             # Get insight config
#   posthog.sh insight-test <id>        # Execute query, check for data
#   posthog.sh insight-refresh <id>     # Force cache refresh
#   posthog.sh insight-save <id>        # Set saved=true
#   posthog.sh insight-delete <id>      # Delete insight
#   posthog.sh triage                   # Scan for issues
#   posthog.sh triage-fix               # Auto-fix not_saved
#
# LLM (requires $ai_generation events):
#   posthog.sh llm [hours]              # Summary: calls, latency, tokens, cost
#   posthog.sh llm-slow [hours] [n]     # Top N slowest calls
#   posthog.sh llm-by-type [hours]      # Breakdown by span_name

set -euo pipefail

# Config - set in .env or environment
PROJECT_ID="${POSTHOG_PROJECT_ID:-}"
API_BASE="${POSTHOG_API_BASE:-https://us.i.posthog.com}"

# Find project root (look for .env file)
find_env() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.env" ]] && echo "$dir/.env" && return
        dir="$(dirname "$dir")"
    done
}

# Load config from .env
POSTHOG_KEY="${POSTHOG_KEY:-}"
for _env_file in "$(find_env)" "$HOME/.env"; do
    [[ -f "$_env_file" ]] || continue
    [[ -z "$POSTHOG_KEY" ]] && POSTHOG_KEY=$(grep -E '^POSTHOG_PERSONAL_API_KEY=' "$_env_file" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'" || true)
    [[ -z "${PROJECT_ID:-}" ]] && PROJECT_ID=$(grep -E '^POSTHOG_PROJECT_ID=' "$_env_file" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'" || true)
done
unset _env_file

# Check jq
command -v jq >/dev/null || { echo '{"error":"missing_jq","fix":"brew install jq"}'; exit 1; }

# Handle help before requiring API key
case "${1:-help}" in
    help|--help|-h)
        cat <<'EOF'
posthog.sh - Query PostHog analytics (agent-friendly)

Explore:
  events [hours]           Event distribution (default: 24h)
  trends <event> [brk] [h] Run trends query with optional breakdown (default: 24h)
  raw <event> [n] [h]      Raw events (default: 20 events, 24h)

Dashboards:
  dashboards               List all dashboards with URLs
  dashboard <name>         Get dashboard by name (partial match)
  dashboard-detail <id>    Full dashboard: filters, tiles, insight configs

Insights:
  insight <id>             Get insight config (query, filters, last_refresh)
  insight-test <id>        Execute insight query, check if returns data
  insight-refresh <id>     Force refresh insight cache
  insight-save <id>        Set saved=true (required for dashboard render)
  insight-delete <id>      Delete an insight
  triage                   Scan all insights for issues (not_saved, wrong_wrapper)
  triage-fix               Auto-fix all not_saved insights

LLM (requires $ai_generation events):
  llm [hours]              Summary: calls, latency, tokens, cost (default: 1h)
  llm-slow [hours] [n]     Top N slowest calls (default: 1h, 10)
  llm-by-type [hours]      Breakdown by span_name (default: 1h)

All output is JSON. Errors have {error, message, fix/hint} structure.
EOF
        exit 0
        ;;
esac

# Now require API key for actual commands
if [[ -z "${POSTHOG_KEY:-}" ]]; then
    echo '{"error":"missing_api_key","fix":"export POSTHOG_KEY=phx_... or add POSTHOG_PERSONAL_API_KEY to .env"}'
    exit 1
fi
if [[ "$POSTHOG_KEY" == phc_* ]]; then
    echo '{"error":"wrong_key_type","message":"Found project key (phc_), need personal key (phx_)","fix":"https://us.posthog.com/settings/user-api-keys"}'
    exit 1
fi
if [[ -z "${PROJECT_ID:-}" ]]; then
    echo '{"error":"missing_project_id","fix":"export POSTHOG_PROJECT_ID=... or add POSTHOG_PROJECT_ID to .env"}'
    exit 1
fi

api_get() {
    curl -s -m 30 "${API_BASE}/api/projects/${PROJECT_ID}${1}" \
        -H "Authorization: Bearer $POSTHOG_KEY" || echo '{"detail":"curl_failed"}'
}

api_post() {
    curl -s -m 60 -X POST "${API_BASE}/api/projects/${PROJECT_ID}${1}" \
        -H "Authorization: Bearer $POSTHOG_KEY" \
        -H "Content-Type: application/json" \
        -d "$2" || echo '{"detail":"curl_failed"}'
}

api_patch() {
    curl -s -m 60 -X PATCH "${API_BASE}/api/projects/${PROJECT_ID}${1}" \
        -H "Authorization: Bearer $POSTHOG_KEY" \
        -H "Content-Type: application/json" \
        -d "$2" || echo '{"detail":"curl_failed"}'
}

timestamp_hours_ago() {
    date -u -v-${1}H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d "${1} hours ago" +%Y-%m-%dT%H:%M:%S
}

# =============================================================================
# LLM Commands
# =============================================================================

cmd_llm() {
    local hours="${1:-1}"
    local after=$(timestamp_hours_ago "$hours")

    api_get "/events/?event=\$ai_generation&limit=500&after=${after}" | jq --argjson h "$hours" '
        if .detail then {error: "api_error", message: .detail}
        elif (.results | length) == 0 then {status: "no_data", period_hours: $h}
        else
            .results as $e | {
                period_hours: $h,
                calls: ($e | length),
                latency_sec: {
                    total: ([$e[].properties["$ai_latency"] // 0] | add | . * 100 | floor / 100),
                    avg: (([$e[].properties["$ai_latency"] // 0] | add) / ($e | length) | . * 100 | floor / 100),
                    max: ([$e[].properties["$ai_latency"] // 0] | max | . * 100 | floor / 100),
                    min: ([$e[].properties["$ai_latency"] // 0] | min | . * 100 | floor / 100)
                },
                tokens: {
                    input: ([$e[].properties["$ai_input_tokens"] // 0] | add),
                    output: ([$e[].properties["$ai_output_tokens"] // 0] | add)
                },
                cost_usd: ([$e[].properties["$ai_total_cost_usd"] // 0] | add | . * 100000 | floor / 100000),
                models: ([$e[].properties["$ai_model"]] | group_by(.) | map({(.[0] // "unknown"): length}) | add)
            }
        end'
}

cmd_llm_slow() {
    local hours="${1:-1}"
    local limit="${2:-10}"
    local after=$(timestamp_hours_ago "$hours")

    api_get "/events/?event=\$ai_generation&limit=500&after=${after}" | jq --argjson limit "$limit" --argjson h "$hours" '
        if .detail then {error: "api_error", message: .detail}
        elif (.results | length) == 0 then {status: "no_data", period_hours: $h}
        else {
            period_hours: $h,
            slowest: [
                .results | sort_by(-.properties["$ai_latency"]) | .[:$limit][] |
                {
                    latency_sec: (.properties["$ai_latency"] | . * 100 | floor / 100),
                    span_name: .properties["$ai_span_name"],
                    model: .properties["$ai_model"],
                    input_tokens: .properties["$ai_input_tokens"],
                    output_tokens: .properties["$ai_output_tokens"],
                    custom: (.properties | with_entries(select(.key | startswith("$") | not))),
                    timestamp: .timestamp[:19]
                }
            ]
        } end'
}

cmd_llm_by_type() {
    local hours="${1:-1}"
    local after=$(timestamp_hours_ago "$hours")

    api_get "/events/?event=\$ai_generation&limit=500&after=${after}" | jq --argjson h "$hours" '
        if .detail then {error: "api_error", message: .detail}
        elif (.results | length) == 0 then {status: "no_data", period_hours: $h}
        else {
            period_hours: $h,
            by_type: [
                .results | group_by(.properties["$ai_span_name"] // "unknown") | .[] |
                {
                    span_name: (.[0].properties["$ai_span_name"] // "unknown"),
                    calls: length,
                    latency_sec: {
                        total: ([.[].properties["$ai_latency"] // 0] | add | . * 100 | floor / 100),
                        avg: (([.[].properties["$ai_latency"] // 0] | add) / length | . * 100 | floor / 100)
                    },
                    tokens: (([.[].properties["$ai_input_tokens"] // 0] | add) + ([.[].properties["$ai_output_tokens"] // 0] | add)),
                    cost_usd: ([.[].properties["$ai_total_cost_usd"] // 0] | add | . * 100000 | floor / 100000)
                }
            ] | sort_by(-.calls)
        } end'
}

cmd_events() {
    local hours="${1:-24}"
    local after=$(timestamp_hours_ago "$hours")

    api_get "/events/?limit=500&after=${after}" | jq --argjson h "$hours" '
        if .detail then {error: "api_error", message: .detail}
        else {
            period_hours: $h,
            total: (.results | length),
            by_event: (
                [.results[].event] | group_by(.) |
                map({(.[0]): length}) | add // {} |
                to_entries | sort_by(-.value) | from_entries
            ),
            unique_users: ([.results[].distinct_id | select(. != null)] | unique | length)
        } end'
}

# =============================================================================
# Dashboard Commands
# =============================================================================

cmd_dashboards() {
    api_get "/dashboards/" | jq --arg base "https://us.posthog.com/project/${PROJECT_ID}/dashboard" '
        if .detail then {error: "api_error", message: .detail}
        else {
            dashboards: [
                .results[] | select(.deleted | not) |
                {name, id, url: "\($base)/\(.id)"}
            ]
        } end'
}

cmd_dashboard() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        cmd_dashboards
        return
    fi

    # Find dashboard by name (case-insensitive partial match)
    local dashboard_id
    dashboard_id=$(api_get "/dashboards/" | jq -r --arg n "$name" '
        .results[] | select(.deleted | not) |
        select(.name | ascii_downcase | contains($n | ascii_downcase)) |
        .id' | head -1)

    if [[ -z "$dashboard_id" ]]; then
        echo '{"error":"not_found","message":"No dashboard matching: '"$name"'"}'
        return 1
    fi

    api_get "/dashboards/${dashboard_id}/" | jq --arg base "https://us.posthog.com/project/$PROJECT_ID/dashboard" '
        if .detail then {error: "api_error", message: .detail}
        else {
            name,
            id,
            url: "\($base)/\(.id)",
            insights: [.tiles[].insight | select(. != null) | {name, id}]
        } end'
}

# =============================================================================
# Insight Commands (for debugging "why is my insight empty?")
# =============================================================================

cmd_insight() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo '{"error":"missing_id","usage":"posthog.sh insight <insight_id>","hint":"Get IDs from: posthog.sh dashboard <name>"}'
        return 1
    fi

    # Support both numeric IDs and short IDs (like "lwrsazxj")
    # Short IDs are alphanumeric, numeric IDs are digits only

    api_get "/insights/${id}/" | jq --arg base "https://us.posthog.com/project/$PROJECT_ID/insights" --arg id "$id" '
        if .detail == "Not found." then {error: "not_found", message: "Insight \($id) does not exist"}
        elif .detail then {error: "api_error", message: .detail}
        else {
            id,
            name,
            url: "\($base)/\(.id)",
            saved,
            deleted,
            last_refresh: .last_refresh,
            query_kind: .query.kind,
            query: .query,
            filters: (.filters // {}),
            dashboards: [.dashboards[]?],
            warnings: (
                [
                    if .saved == false then "NOT_SAVED: insight may not render on dashboard" else null end,
                    if .deleted == true then "DELETED: insight is marked as deleted" else null end
                ] | map(select(. != null))
            )
        } end'
}

cmd_insight_test() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo '{"error":"missing_id","usage":"posthog.sh insight-test <insight_id>","hint":"Executes the insight query and returns results"}'
        return 1
    fi

    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        echo '{"error":"invalid_id","message":"Insight ID must be numeric","got":"'"$id"'"}'
        return 1
    fi

    # First get the insight query
    local insight_data
    insight_data=$(api_get "/insights/${id}/")

    # Check if insight exists
    if echo "$insight_data" | jq -e '.detail == "Not found."' >/dev/null 2>&1; then
        echo '{"error":"not_found","message":"Insight '"$id"' does not exist"}'
        return 1
    fi

    # Extract query
    local query
    query=$(echo "$insight_data" | jq -c '.query // empty')

    if [[ -z "$query" ]]; then
        echo '{"error":"no_query","message":"Insight has no query defined","insight_id":'"$id"'}'
        return 1
    fi

    # Execute query
    api_post "/query/" "{\"query\": $query}" | jq --arg id "$id" '
        if .detail then {error: "query_failed", message: .detail, insight_id: $id}
        # DataTableNode: .results is array of arrays (rows), .columns exists
        elif .columns then
            (.results[0] // []) as $row |
            {
                insight_id: $id,
                query_type: "table",
                has_data: ((.results | length) > 0 and ($row | any(. != null))),
                row_count: (.results | length),
                columns: .columns,
                sample_row: $row,
                has_nulls: ($row | any(. == null))
            }
        # TrendsQuery: .results is array of objects with .label, .count, .data
        elif ((.results | type) == "array") and ((.results[0].label // null) != null) then {
            insight_id: $id,
            query_type: "trends",
            has_data: ((.results | length) > 0),
            result_count: (.results | length),
            results: [.results[] | {label: .label, count: .count, data: .data}][:10]
        }
        else {
            insight_id: $id,
            has_data: ((.results | length) > 0),
            result_count: (.results | length),
            raw_response_keys: (keys)
        } end'
}

cmd_insight_refresh() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo '{"error":"missing_id","usage":"posthog.sh insight-refresh <insight_id>"}'
        return 1
    fi

    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        echo '{"error":"invalid_id","message":"Insight ID must be numeric","got":"'"$id"'"}'
        return 1
    fi

    # Trigger refresh by getting with refresh=true
    api_get "/insights/${id}/?refresh=true" | jq --arg id "$id" '
        if .detail == "Not found." then {error: "not_found", message: "Insight \($id) does not exist"}
        elif .detail then {error: "api_error", message: .detail}
        else {
            insight_id: (.id // $id),
            name,
            status: "refreshed",
            last_refresh: .last_refresh
        } end'
}

cmd_insight_save() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo '{"error":"missing_id","usage":"posthog.sh insight-save <insight_id>","hint":"Sets saved=true so insight renders on dashboard"}'
        return 1
    fi

    api_patch "/insights/${id}/" '{"saved": true}' | jq '{id, name, saved}'
}

cmd_insight_delete() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo '{"error":"missing_id","usage":"posthog.sh insight-delete <insight_id>"}'
        return 1
    fi

    api_patch "/insights/${id}/" '{"deleted": true}' | jq '{id, name, deleted}'
}

cmd_triage() {
    echo '{"status":"scanning","message":"Checking all insights for issues..."}' >&2

    api_get "/insights/?limit=200" | jq '
        [.results[] | select(.deleted == false)] |
        {
            total: length,
            issues: {
                not_saved: [.[] | select(.saved == false and ([.dashboards[]?] | length) > 0) | {id, name: .name[:35]}],
                wrong_wrapper: [.[] | select(
                    ([.dashboards[]?] | length) > 0 and
                    .query.kind != "InsightVizNode" and
                    .query.kind != "DataTableNode" and
                    .query.kind != null
                ) | {id, name: .name[:35], query_kind: .query.kind}]
            },
            summary: {
                not_saved_count: ([.[] | select(.saved == false and ([.dashboards[]?] | length) > 0)] | length),
                wrong_wrapper_count: ([.[] | select(
                    ([.dashboards[]?] | length) > 0 and
                    .query.kind != "InsightVizNode" and
                    .query.kind != "DataTableNode" and
                    .query.kind != null
                )] | length),
                healthy: ([.[] | select(
                    .saved == true and
                    ([.dashboards[]?] | length) > 0 and
                    (.query.kind == "InsightVizNode" or .query.kind == "DataTableNode" or .query.kind == null)
                )] | length)
            }
        }'
}

cmd_triage_fix() {
    echo '{"status":"fixing","message":"Fixing all not_saved insights..."}' >&2

    # Get all unsaved insights on dashboards
    local ids
    ids=$(api_get "/insights/?limit=200" | jq -r '
        [.results[] | select(.deleted == false and .saved == false and ([.dashboards[]?] | length) > 0) | .id] | .[]')

    if [[ -z "$ids" ]]; then
        echo '{"status":"ok","message":"No unsaved insights found","fixed":0}'
        return 0
    fi

    local count=0
    for id in $ids; do
        api_patch "/insights/${id}/" '{"saved": true}' > /dev/null
        count=$((count + 1))
    done

    echo "{\"status\":\"fixed\",\"count\":$count}"
}

cmd_dashboard_detail() {
    local input="${1:-}"
    if [[ -z "$input" ]]; then
        echo '{"error":"missing_input","usage":"posthog.sh dashboard-detail <id|name>","hint":"Use dashboard ID or partial name match"}'
        return 1
    fi

    local dashboard_id="$input"

    # If not numeric, search by name
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        dashboard_id=$(api_get "/dashboards/" | jq -r --arg n "$input" '
            .results[] | select(.deleted | not) |
            select(.name | ascii_downcase | contains($n | ascii_downcase)) |
            .id' | head -1)

        if [[ -z "$dashboard_id" ]]; then
            echo '{"error":"not_found","message":"No dashboard matching: '"$input"'","hint":"Use: posthog.sh dashboards to list all"}'
            return 1
        fi
    fi

    api_get "/dashboards/${dashboard_id}/" | jq --arg base "https://us.posthog.com/project/$PROJECT_ID" '
        if .detail == "Not found." then {error: "not_found", message: "Dashboard does not exist"}
        elif .detail then {error: "api_error", message: .detail}
        else {
            id,
            name,
            url: "\($base)/dashboard/\(.id)",
            filters: (.filters // {}),
            tiles: [
                .tiles[] | select(.insight != null) | {
                    insight_id: .insight.id,
                    insight_name: .insight.name,
                    insight_url: "\($base)/insights/\(.insight.id)",
                    query_kind: .insight.query.kind,
                    last_refresh: .insight.last_refresh,
                    filters: (.insight.filters // {})
                }
            ]
        } end'
}

cmd_trends() {
    local event="${1:-}"
    local breakdown="${2:-}"
    local hours="${3:-24}"

    if [[ -z "$event" ]]; then
        echo '{"error":"missing_event","usage":"posthog.sh trends <event> [breakdown_property] [hours]","example":"posthog.sh trends $pageview $browser 24"}'
        return 1
    fi

    local query
    if [[ -n "$breakdown" ]]; then
        query='{
            "kind": "TrendsQuery",
            "series": [{"kind": "EventsNode", "math": "total", "event": "'"$event"'"}],
            "interval": "day",
            "dateRange": {"date_from": "-'"$hours"'h"},
            "breakdownFilter": {"breakdown": "'"$breakdown"'", "breakdown_type": "event"}
        }'
    else
        query='{
            "kind": "TrendsQuery",
            "series": [{"kind": "EventsNode", "math": "total", "event": "'"$event"'"}],
            "interval": "day",
            "dateRange": {"date_from": "-'"$hours"'h"}
        }'
    fi

    api_post "/query/" "{\"query\": $query}" | jq --arg e "$event" --arg h "$hours" --arg b "$breakdown" '
        if .detail then {error: "query_failed", message: .detail}
        elif (.results | length) == 0 then {
            status: "no_data",
            event: $e,
            period_hours: ($h | tonumber),
            breakdown: (if $b == "" then null else $b end)
        }
        else {
            event: $e,
            period_hours: ($h | tonumber),
            breakdown: (if $b == "" then null else $b end),
            total: ([.results[].count] | add),
            results: [.results[] | {label: (.label // $e), count, data}]
        } end'
}

# =============================================================================
# Query Commands
# =============================================================================

cmd_raw() {
    local event="${1:-}"
    local limit="${2:-20}"
    local hours="${3:-24}"

    if [[ -z "$event" ]]; then
        echo '{"error":"missing_event","usage":"posthog.sh raw <event_name> [limit] [hours]"}'
        return 1
    fi

    local after=$(timestamp_hours_ago "$hours")

    api_get "/events/?event=${event}&limit=${limit}&after=${after}" | jq '
        if .detail then {error: "api_error", message: .detail}
        else {
            count: (.results | length),
            events: [.results[] | {timestamp: .timestamp[:19], properties}]
        } end'
}

case "${1:-help}" in
    events)           cmd_events "${2:-24}" ;;
    trends)           cmd_trends "${2:-}" "${3:-}" "${4:-24}" ;;
    raw)              cmd_raw "${2:-}" "${3:-20}" "${4:-24}" ;;
    dashboards)       cmd_dashboards ;;
    dashboard)        cmd_dashboard "${2:-}" ;;
    dashboard-detail) cmd_dashboard_detail "${2:-}" ;;
    insight)          cmd_insight "${2:-}" ;;
    insight-test)     cmd_insight_test "${2:-}" ;;
    insight-refresh)  cmd_insight_refresh "${2:-}" ;;
    insight-save)     cmd_insight_save "${2:-}" ;;
    insight-delete)   cmd_insight_delete "${2:-}" ;;
    triage)           cmd_triage ;;
    triage-fix)       cmd_triage_fix ;;
    llm)              cmd_llm "${2:-1}" ;;
    llm-slow)         cmd_llm_slow "${2:-1}" "${3:-10}" ;;
    llm-by-type)      cmd_llm_by_type "${2:-1}" ;;
    *)                echo '{"error":"unknown_command","command":"'"$1"'","available":["events","trends","raw","dashboards","dashboard","dashboard-detail","insight","insight-test","insight-refresh","insight-save","insight-delete","triage","triage-fix","llm","llm-slow","llm-by-type","help"]}' ;;
esac
