#!/bin/bash
# trigger.sh - Query Trigger.dev runs (agent-friendly)
# All output is JSON to stdout. No stderr noise.
#
# Runs:
#   trigger.sh runs [n]              # Recent runs (default: 20)
#   trigger.sh failed [n]            # Failed runs only
#   trigger.sh running               # Currently executing runs
#   trigger.sh task <name> [n]       # Runs for specific task
#
# Details:
#   trigger.sh run <run_id>          # Full run details with error
#   trigger.sh error <run_id>        # Just error info from a run
#
# Debug:
#   trigger.sh tasks                 # List known task identifiers

set -euo pipefail

API_BASE="https://api.trigger.dev/api"

# Find project root (look for .env file)
find_env() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.env" ]] && echo "$dir/.env" && return
        dir="$(dirname "$dir")"
    done
}

# Load API key from multiple locations
TRIGGER_SECRET_KEY="${TRIGGER_SECRET_KEY:-}"
if [[ -z "$TRIGGER_SECRET_KEY" ]]; then
    for env_file in "$(find_env)" "$HOME/.env"; do
        [[ -f "$env_file" ]] && TRIGGER_SECRET_KEY=$(grep -E '^TRIGGER_SECRET_KEY=' "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d "\"'" || true)
        [[ -n "${TRIGGER_SECRET_KEY:-}" ]] && break
    done
fi

# Check jq
command -v jq >/dev/null || { echo '{"error":"missing_jq","fix":"brew install jq or apt install jq"}'; exit 1; }

# Handle help before requiring API key
case "${1:-help}" in
    help|--help|-h)
        cat <<'EOF'
trigger.sh - Query Trigger.dev runs

Runs:
  runs [n]              Recent runs (default: 20)
  failed [n]            Failed runs only (default: 20)
  running               Currently executing runs
  task <name> [n]       Runs for specific task (default: 20)

Details:
  run <run_id>          Full run details with error info
  error <run_id>        Just error info from a run

Debug:
  tasks                 List known task identifiers from recent runs

All output is JSON. Errors have {error, message, fix} structure.
EOF
        exit 0
        ;;
esac

# Now require API key for actual commands
if [[ -z "${TRIGGER_SECRET_KEY:-}" ]]; then
    echo '{"error":"missing_api_key","fix":"export TRIGGER_SECRET_KEY=tr_... or add to .env"}'
    exit 1
fi

api_get() {
    local path="$1"
    curl -s -g -m 30 "${API_BASE}${path}" \
        -H "Authorization: Bearer $TRIGGER_SECRET_KEY" \
        -H "Accept: application/json" 2>/dev/null || echo '{"error":"curl_failed"}'
}

# =============================================================================
# Runs Commands
# =============================================================================

cmd_runs() {
    local limit="${1:-20}"

    api_get "/v1/runs?page[size]=${limit}" | jq '
        if .error then .
        elif .data == null then {error: "unexpected_response"}
        else {
            count: (.data | length),
            runs: [
                .data[] | {
                    id,
                    task: .taskIdentifier,
                    status,
                    created: .createdAt[:19],
                    duration_ms: .durationMs,
                    is_test: .isTest
                }
            ]
        } end'
}

cmd_failed() {
    local limit="${1:-20}"

    api_get "/v1/runs?page[size]=${limit}&filter[status]=FAILED,CRASHED,SYSTEM_FAILURE" | jq '
        if .error then .
        elif .data == null then {error: "unexpected_response"}
        else {
            count: (.data | length),
            failed_runs: [
                .data[] | {
                    id,
                    task: .taskIdentifier,
                    status,
                    created: .createdAt[:19],
                    duration_ms: .durationMs
                }
            ]
        } end'
}

cmd_running() {
    api_get "/v1/runs?page[size]=50&filter[status]=QUEUED,EXECUTING,REATTEMPTING" | jq '
        if .error then .
        elif .data == null then {error: "unexpected_response"}
        else {
            count: (.data | length),
            running: [
                .data[] | {
                    id,
                    task: .taskIdentifier,
                    status,
                    started: .createdAt[:19]
                }
            ]
        } end'
}

cmd_task() {
    local task="${1:-}"
    local limit="${2:-20}"

    if [[ -z "$task" ]]; then
        echo '{"error":"missing_task","usage":"trigger.sh task <task-identifier> [limit]"}'
        return 1
    fi

    api_get "/v1/runs?page[size]=${limit}&filter[taskIdentifier]=${task}" | jq --arg task "$task" '
        if .error then .
        elif .data == null then {error: "unexpected_response"}
        else {
            task: $task,
            count: (.data | length),
            runs: [
                .data[] | {
                    id,
                    status,
                    created: .createdAt[:19],
                    duration_ms: .durationMs
                }
            ]
        } end'
}

# =============================================================================
# Detail Commands
# =============================================================================

cmd_run() {
    local run_id="${1:-}"

    if [[ -z "$run_id" ]]; then
        echo '{"error":"missing_run_id","usage":"trigger.sh run <run_id>"}'
        return 1
    fi

    # Normalize run_id (add prefix if missing)
    [[ "$run_id" != run_* ]] && run_id="run_${run_id}"

    api_get "/v3/runs/${run_id}" | jq '
        if .id == null then {error: "run_not_found"}
        else {
            id,
            task: .taskIdentifier,
            status,
            created: .createdAt[:19],
            started: (.startedAt[:19] // null),
            finished: (.finishedAt[:19] // null),
            duration_ms: .durationMs,
            is_test: .isTest,
            metadata: (.metadata // null),
            error: (if .error then {
                name: .error.name,
                message: .error.message,
                stack: (.error.stackTrace // null)
            } else null end),
            schedule: (.schedule.id // null)
        } end'
}

cmd_error() {
    local run_id="${1:-}"

    if [[ -z "$run_id" ]]; then
        echo '{"error":"missing_run_id","usage":"trigger.sh error <run_id>"}'
        return 1
    fi

    # Normalize run_id (add prefix if missing)
    [[ "$run_id" != run_* ]] && run_id="run_${run_id}"

    api_get "/v3/runs/${run_id}" | jq '
        if .id == null then {error: "run_not_found"}
        elif .error then {
            run_id: .id,
            task: .taskIdentifier,
            status,
            name: .error.name,
            message: .error.message,
            stack: (.error.stackTrace // null)
        }
        else {status: "no_error", run_id: .id}
        end'
}

# =============================================================================
# Debug Commands
# =============================================================================

cmd_tasks() {
    # Get recent runs and extract unique task identifiers
    api_get "/v1/runs?page[size]=100" | jq '
        if .error then .
        elif .data == null then {error: "unexpected_response"}
        else {
            tasks: ([.data[].taskIdentifier] | unique | sort)
        } end'
}

case "${1:-help}" in
    runs)     cmd_runs "${2:-20}" ;;
    failed)   cmd_failed "${2:-20}" ;;
    running)  cmd_running ;;
    task)     cmd_task "${2:-}" "${3:-20}" ;;
    run)      cmd_run "${2:-}" ;;
    error)    cmd_error "${2:-}" ;;
    tasks)    cmd_tasks ;;
    *)        echo '{"error":"unknown_command","command":"'"$1"'","available":["runs","failed","running","task","run","error","tasks","help"]}' ;;
esac
