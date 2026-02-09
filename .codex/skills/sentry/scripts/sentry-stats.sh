#!/bin/bash
# sentry-stats.sh - Query Sentry for errors, performance, and traces
# Requires: curl, jq
#
# Usage:
#   ./scripts/sentry-stats.sh errors           # Recent unresolved issues
#   ./scripts/sentry-stats.sh issues [query]   # Search issues
#   ./scripts/sentry-stats.sh issue <id>       # Single issue details
#   ./scripts/sentry-stats.sh events <issue>   # Events for an issue
#   ./scripts/sentry-stats.sh spans [endpoint] # Slow spans
#   ./scripts/sentry-stats.sh trace <id>       # Trace breakdown
#   ./scripts/sentry-stats.sh perf [period]    # Transaction performance
#   ./scripts/sentry-stats.sh releases         # Recent releases

set -euo pipefail

# Config - set in .env or environment
ORG="${SENTRY_ORG:-}"
PROJECT="${SENTRY_PROJECT:-}"
PROJECT_ID="${SENTRY_PROJECT_ID:-}"
API_BASE="https://sentry.io/api/0"

# Find project root (look for .env file)
find_env() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.env" ]] && echo "$dir/.env" && return
        dir="$(dirname "$dir")"
    done
}

# Load config and API key from env vars or .env file
load_config() {
    local env_file
    for env_file in "$(find_env)" "$HOME/.env"; do
        [[ -f "$env_file" ]] || continue
        [[ -z "${SENTRY_TOKEN:-}" ]] && SENTRY_TOKEN=$(grep -E '^SENTRY_AUTH_TOKEN=' "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'" || true)
        [[ -z "${ORG:-}" ]] && ORG=$(grep -E '^SENTRY_ORG=' "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'" || true)
        [[ -z "${PROJECT:-}" ]] && PROJECT=$(grep -E '^SENTRY_PROJECT=' "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'" || true)
        [[ -z "${PROJECT_ID:-}" ]] && PROJECT_ID=$(grep -E '^SENTRY_PROJECT_ID=' "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'" || true)
    done
    if [[ -z "${SENTRY_TOKEN:-}" ]]; then
        echo '{"error":"missing_api_key","fix":"Set SENTRY_TOKEN or add SENTRY_AUTH_TOKEN to .env"}'
        exit 1
    fi
}

# Backwards compat alias
load_key() { load_config; }

# URL encode (pure bash)
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) o="$c" ;;
            *) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="$o"
    done
    echo "$encoded"
}

# Format duration in ms to human readable
format_duration() {
    local ms="$1"
    if (( $(echo "$ms >= 60000" | bc -l) )); then
        echo "$(echo "scale=1; $ms/60000" | bc)min"
    elif (( $(echo "$ms >= 1000" | bc -l) )); then
        echo "$(echo "scale=1; $ms/1000" | bc)s"
    else
        echo "${ms%.*}ms"
    fi
}

api_get() {
    curl -s -m 30 "${API_BASE}${1}" -H "Authorization: Bearer $SENTRY_TOKEN" || echo '{"detail":"Request failed"}'
}

api_get_org() {
    api_get "/organizations/${ORG}${1}"
}

api_get_project() {
    api_get "/projects/${ORG}/${PROJECT}${1}"
}

cmd_errors() {
    local limit="${1:-10}"
    echo "# Unresolved Errors (limit: $limit)" >&2

    api_get_project "/issues/?query=is:unresolved&limit=${limit}" | jq '
        if type == "object" and .detail then
            {error: "api_error", message: .detail}
        elif length == 0 then
            {status: "ok", message: "No unresolved issues"}
        else
            {
                count: length,
                issues: [.[] | {
                    id,
                    shortId,
                    title: .title[:80],
                    culprit: (.culprit // "")[:60],
                    count: (.count | tonumber),
                    userCount,
                    firstSeen: .firstSeen[:10],
                    lastSeen: .lastSeen[:10],
                    level: (.level // "error")
                }]
            }
        end
    '
}

cmd_issues() {
    local query="${1:-is:unresolved}"
    local limit="${2:-20}"
    local encoded_query=$(urlencode "$query")
    echo "# Issues: $query (limit: $limit)" >&2

    api_get_project "/issues/?query=${encoded_query}&limit=${limit}" | jq --arg q "$query" '
        if type == "object" and .detail then
            {error: "api_error", message: .detail}
        else
            {
                query: $q,
                count: length,
                issues: [.[] | {
                    id,
                    shortId,
                    title: .title[:80],
                    culprit: (.culprit // "")[:60],
                    count: (.count | tonumber),
                    userCount,
                    lastSeen: .lastSeen[:16] | gsub("T"; " "),
                    status: (.status // "unknown")
                }]
            }
        end
    '
}

cmd_issue() {
    local issue_id="${1:-}"
    [[ -z "$issue_id" ]] && { echo '{"error":"missing_issue_id","usage":"sentry-stats.sh issue <id>"}'; exit 1; }
    echo "# Issue: $issue_id" >&2

    api_get "/issues/${issue_id}/" | jq '
        if .detail then
            {error: "api_error", message: .detail, issue_id: "'"$issue_id"'"}
        else
            {
                id,
                shortId,
                title,
                culprit,
                level,
                status,
                count: (.count | tonumber),
                userCount,
                firstSeen: .firstSeen[:16] | gsub("T"; " "),
                lastSeen: .lastSeen[:16] | gsub("T"; " "),
                metadata: (.metadata | {type, value: (.value // "")[:200], filename, function} | with_entries(select(.value != null and .value != ""))),
                permalink
            }
        end
    '
}

cmd_events() {
    local issue_id="${1:-}"
    local limit="${2:-10}"
    [[ -z "$issue_id" ]] && { echo '{"error":"missing_issue_id","usage":"sentry-stats.sh events <issue_id> [limit]"}'; exit 1; }
    echo "# Events for issue $issue_id (limit: $limit)" >&2

    api_get "/issues/${issue_id}/events/?limit=${limit}" | jq --arg id "$issue_id" '
        if type == "object" and .detail then
            {error: "api_error", message: .detail, issue_id: $id}
        elif length == 0 then
            {status: "no_events", issue_id: $id, message: "No events found"}
        else
            {
                issue_id: $id,
                count: length,
                events: [.[] | {
                    id: .eventID,
                    timestamp: .dateCreated[:16] | gsub("T"; " "),
                    message: ((.message // .title // "")[:100]),
                    tags: ([.tags[] | select(.key == "environment" or .key == "release" or .key == "transaction" or .key == "url")] | from_entries)
                }]
            }
        end
    '
}

cmd_spans() {
    local endpoint_filter="${1:-}"
    local period="${2:-14d}"
    local limit="${3:-20}"

    local query=""
    if [[ -n "$endpoint_filter" ]]; then
        query="span.description:${endpoint_filter}"
        echo "# Filter: $query" >&2
    else
        query="!span.name:middleware.starlette"
        echo "# Filter: excluding middleware" >&2
    fi
    echo "# Slow Spans (period: $period, limit: $limit)" >&2

    local encoded_query=$(urlencode "$query")

    api_get_org "/events/?dataset=spans&project=${PROJECT_ID}&statsPeriod=${period}&query=${encoded_query}&field=id&field=trace&field=span.name&field=span.description&field=span.duration&field=transaction&field=timestamp&sort=-span.duration&per_page=${limit}" | jq --arg p "$period" '
        if .detail then
            {error: "api_error", message: .detail}
        elif (.data | length) == 0 then
            {status: "no_data", message: "No spans found", period: $p}
        else
            def fmt_dur: if . >= 60000 then "\(. / 60000 | . * 10 | floor / 10)min"
                        elif . >= 1000 then "\(. / 1000 | . * 10 | floor / 10)s"
                        else "\(. | floor)ms" end;
            {
                period: $p,
                count: (.data | length),
                spans: [.data[] | {
                    id,
                    trace_id: .trace,
                    name: ."span.name",
                    description: (."span.description" // "")[:60],
                    duration: (."span.duration" | fmt_dur),
                    duration_ms: ."span.duration",
                    transaction,
                    timestamp: .timestamp[:16] | gsub("T"; " ")
                }],
                stats: {
                    max_ms: ([.data[]."span.duration"] | max),
                    min_ms: ([.data[]."span.duration"] | min),
                    avg_ms: ([.data[]."span.duration"] | add / length | floor),
                    max_human: ([.data[]."span.duration"] | max | fmt_dur),
                    avg_human: ([.data[]."span.duration"] | add / length | fmt_dur)
                }
            }
        end
    '
}

cmd_trace() {
    local trace_id="${1:-}"
    [[ -z "$trace_id" ]] && { echo '{"error":"missing_trace_id","usage":"sentry-stats.sh trace <trace_id>","hint":"Get trace_id from spans command"}'; exit 1; }
    echo "# Trace: $trace_id" >&2

    api_get_org "/events/?dataset=spans&project=${PROJECT_ID}&query=trace:${trace_id}&field=id&field=span.name&field=span.description&field=span.duration&field=timestamp&sort=-span.duration&per_page=100" | jq --arg tid "$trace_id" '
        if .detail then
            {error: "api_error", message: .detail}
        elif (.data | length) == 0 then
            {status: "no_data", message: "Trace not found or expired"}
        else
            def fmt_dur: if . >= 60000 then "\(. / 60000 | . * 10 | floor / 10)min"
                        elif . >= 1000 then "\(. / 1000 | . * 10 | floor / 10)s"
                        else "\(. | floor)ms" end;

            # Filter out middleware for analysis
            (.data | [.[] | select(."span.name" | test("middleware"; "i") | not)]) as $filtered |

            {
                trace_id: $tid,
                span_count: (.data | length),
                total_duration: ([.data[]."span.duration"] | max | fmt_dur),
                by_operation: ([$filtered | group_by(."span.name")[] | {
                    operation: .[0]."span.name",
                    count: length,
                    total_ms: ([.[]."span.duration"] | add | floor),
                    total: ([.[]."span.duration"] | add | fmt_dur),
                    avg: ([.[]."span.duration"] | add / length | fmt_dur),
                    max: ([.[]."span.duration"] | max | fmt_dur)
                }] | sort_by(-.total_ms)[:10]),
                slowest_spans: [$filtered[:10][] | {
                    name: ."span.name",
                    description: (."span.description" // "")[:50],
                    duration: (."span.duration" | fmt_dur),
                    duration_ms: ."span.duration"
                }]
            }
        end
    '
}

cmd_perf() {
    local period="${1:-24h}"
    echo "# Performance Summary (period: $period)" >&2

    api_get_org "/events/?dataset=spans&project=${PROJECT_ID}&statsPeriod=${period}&field=transaction&field=count()&field=avg(span.duration)&field=p95(span.duration)&query=span.op:http.server&sort=-p95(span.duration)&per_page=15" | jq --arg p "$period" '
        if .detail then
            {error: "api_error", message: .detail}
        elif (.data | length) == 0 then
            {status: "no_data", message: "No transaction data", period: $p}
        else
            def fmt_dur: if . == null then "N/A"
                        elif . >= 60000 then "\(. / 60000 | . * 10 | floor / 10)min"
                        elif . >= 1000 then "\(. / 1000 | . * 10 | floor / 10)s"
                        else "\(. | floor)ms" end;
            {
                period: $p,
                endpoint_count: (.data | length),
                transactions: [.data[] | {
                    endpoint: .transaction,
                    requests: (."count()" | floor),
                    avg: (."avg(span.duration)" | fmt_dur),
                    avg_ms: (."avg(span.duration)" // 0 | floor),
                    p95: (."p95(span.duration)" | fmt_dur),
                    p95_ms: (."p95(span.duration)" // 0 | floor)
                }]
            }
        end
    '
}

cmd_releases() {
    local limit="${1:-5}"
    echo "# Recent Releases (limit: $limit)" >&2

    api_get_org "/releases/?project=${PROJECT_ID}&per_page=${limit}" | jq '
        if type == "object" and .detail then
            {error: "api_error", message: .detail}
        elif length == 0 then
            {status: "no_data", message: "No releases found"}
        else
            {
                count: length,
                releases: [.[] | {
                    version: (.shortVersion // .version)[:40],
                    created: .dateCreated[:16] | gsub("T"; " "),
                    new_issues: (.newGroups // 0),
                    authors: (.authors | length),
                    commits: (.commitCount // 0)
                }]
            }
        end
    '
}

cmd_config() {
    echo "# Sentry Config" >&2
    local configured="false"
    [[ -n "${SENTRY_TOKEN:-}" ]] && configured="true"
    jq -n --arg org "$ORG" --arg proj "$PROJECT" --arg pid "$PROJECT_ID" --arg base "$API_BASE" --argjson conf "$configured" \
        '{org: $org, project: $proj, project_id: $pid, api_base: $base, token_configured: $conf}'
}

cmd_help() {
    cat <<EOF
Sentry Stats - Query errors, performance, and traces
Requires: curl, jq

USAGE:
    $0 <command> [args]

COMMANDS:
    errors [limit]              Unresolved issues (default: 10)
    issues [query] [limit]      Search issues (default: "is:unresolved")
    issue <id>                  Single issue details
    events <issue_id> [limit]   Events for an issue
    spans [endpoint] [period]   Slow spans (default: 14d, excludes middleware)
    trace <trace_id>            Trace breakdown by operation
    perf [period]               Transaction performance by p95
    releases [limit]            Recent releases
    config                      Show configuration
    help                        Show this help

SETUP:
    export SENTRY_TOKEN=...     # or add SENTRY_AUTH_TOKEN to .env
    Get token: https://sentry.io/settings/auth-tokens/

EXAMPLES:
    $0 errors                   # Quick check for unresolved issues
    $0 issues "level:error"     # Search for error-level issues
    $0 spans /cluster 7d        # Slow /cluster spans over 7 days
    $0 trace <trace_id>         # Get trace_id from spans output
    $0 perf 7d                  # Transaction perf over 7 days
EOF
}

# Check jq is available
command -v jq >/dev/null || { echo '{"error":"missing_dependency","fix":"brew install jq"}'; exit 1; }

# Handle help before requiring API key
case "${1:-help}" in
    help|--help|-h) cmd_help; exit 0 ;;
esac

load_key

if [[ -z "${ORG:-}" || -z "${PROJECT:-}" || -z "${PROJECT_ID:-}" ]]; then
    echo '{"error":"missing_config","fix":"Add SENTRY_ORG, SENTRY_PROJECT, SENTRY_PROJECT_ID to .env"}'
    exit 1
fi

case "${1:-help}" in
    errors)     cmd_errors "${2:-10}" ;;
    issues)     cmd_issues "${2:-is:unresolved}" "${3:-20}" ;;
    issue)      cmd_issue "${2:-}" ;;
    events)     cmd_events "${2:-}" "${3:-10}" ;;
    spans)      cmd_spans "${2:-}" "${3:-14d}" "${4:-20}" ;;
    trace)      cmd_trace "${2:-}" ;;
    perf)       cmd_perf "${2:-24h}" ;;
    releases)   cmd_releases "${2:-5}" ;;
    config)     cmd_config ;;
    help|--help|-h) cmd_help ;;
    *)          echo '{"error":"unknown_command","command":"'"$1"'","available":"errors|issues|issue|events|spans|trace|perf|releases|config|help"}'; exit 1 ;;
esac
