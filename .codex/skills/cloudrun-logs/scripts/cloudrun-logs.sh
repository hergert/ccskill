#!/bin/bash
# cloudrun-logs.sh - Zero-friction Cloud Run debugging

set -e

CONFIG_FILE=".cloudrun-logs"
ERROR_PATTERN="(error|exception|fatal|panic|traceback|failed|timeout|denied|refused|crash)"

# Find project root (look for config file or .env)
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.cloudrun-logs" ]] && echo "$dir" && return
        [[ -f "$dir/.env" ]] && echo "$dir" && return
        dir="$(dirname "$dir")"
    done
    echo "$PWD"
}

# === CONFIG ===
load_config() {
    local project_root
    project_root="$(find_project_root)"
    [[ -f "$project_root/$CONFIG_FILE" ]] && source "$project_root/$CONFIG_FILE" || true
    [[ -f "$HOME/.cloudrun-logs" ]] && source "$HOME/.cloudrun-logs" || true
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
SERVICE="$SERVICE"
PROJECT="$PROJECT"
ACCOUNT="$ACCOUNT"
REGION="$REGION"
EOF
    echo "Saved to $CONFIG_FILE" >&2
}

# === AUTH ===
ensure_auth() {
    local current_account
    current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)

    if [[ -z "$current_account" ]]; then
        gcloud auth login --brief || exit 1
        current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    fi

    if [[ -n "$ACCOUNT" && "$current_account" != "$ACCOUNT" ]]; then
        echo "Switching account: $current_account → $ACCOUNT" >&2
        gcloud config set account "$ACCOUNT"
    fi

    if [[ -n "$PROJECT" ]]; then
        gcloud config set project "$PROJECT" 2>/dev/null
    fi
}

# === VALIDATION ===
require_config() {
    if [[ -z "$SERVICE" || -z "$REGION" ]]; then
        echo '{"error":"not_configured","fix":"run: '$0' init"}'
        exit 1
    fi
}

validate_service() {
    if ! gcloud run services describe "$SERVICE" --region="$REGION" &>/dev/null; then
        echo '{"error":"service_not_found","service":"'$SERVICE'","region":"'$REGION'","fix":"run: '$0' init"}'
        exit 1
    fi
}

# === CONTEXT (always show where we are) ===
show_context() {
    echo "# $SERVICE | $PROJECT | $REGION" >&2
}

# === LOGS HELPER (fallback for gcloud bugs) ===
fetch_logs() {
    local limit="${1:-100}"

    # Try gcloud run services logs first (|| true to prevent set -e exit)
    local output
    output=$(gcloud run services logs read "$SERVICE" --region="$REGION" --limit="$limit" 2>&1 || true)

    # Check for gcloud crash or empty output
    if [[ "$output" == *"gcloud crashed"* ]] || [[ "$output" == *"ERROR"* ]] || [[ -z "$output" ]]; then
        echo "# Fallback to logging API" >&2
        gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE" \
            --limit="$limit" \
            --format="table(timestamp.date('%H:%M:%S'),severity,textPayload,jsonPayload.message)"
    else
        echo "$output"
    fi
}

# === MAIN ===
load_config

case "${1:-errors}" in
    init)
        echo "=== Setup ===" >&2
        gcloud auth login --brief
        echo ""
        echo "Available projects:"
        gcloud projects list --format="value(projectId)" | head -10
        read -p "Project: " PROJECT
        gcloud config set project "$PROJECT"

        echo ""
        echo "Available services:"
        gcloud run services list --format="value(SERVICE,REGION)"
        read -p "Service: " SERVICE

        REGION=$(gcloud run services list --filter="SERVICE:$SERVICE" --format="value(REGION)" | head -1)
        [[ -z "$REGION" ]] && { echo '{"error":"service_not_found"}'; exit 1; }
        ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")

        save_config
        echo '{"status":"configured","service":"'$SERVICE'","project":"'$PROJECT'","region":"'$REGION'"}'
        ;;

    config)
        require_config
        echo '{"service":"'$SERVICE'","project":"'$PROJECT'","account":"'$ACCOUNT'","region":"'$REGION'"}'
        ;;

    errors|"")
        ensure_auth
        require_config
        validate_service
        show_context

        LOGS=$(fetch_logs 100)

        if [[ -z "$LOGS" ]]; then
            echo '{"status":"no_logs","message":"No logs found (logging issue?)"}'
            exit 0
        fi

        ERRORS=$(echo "$LOGS" | grep -i -E "$ERROR_PATTERN" | head -20 || true)

        if [[ -z "$ERRORS" ]]; then
            LATEST=$(echo "$LOGS" | head -1)
            echo '{"status":"ok","message":"No errors in last 100 logs","latest_log":"'"$LATEST"'"}'
        else
            echo '{"status":"errors_found","count":'$(echo "$ERRORS" | wc -l | tr -d ' ')'}'
            echo "$ERRORS"
        fi
        ;;

    recent)
        ensure_auth
        require_config
        validate_service
        show_context
        fetch_logs 30
        ;;

    all)
        ensure_auth
        require_config
        validate_service
        show_context
        fetch_logs 200
        ;;

    tail)
        ensure_auth
        require_config
        validate_service
        show_context
        DURATION="${2:-30}"
        echo "Tailing for ${DURATION}s (Ctrl+C to stop early)..." >&2
        timeout "$DURATION" gcloud run services logs tail "$SERVICE" --region="$REGION" || true
        ;;

    since)
        # Logs since last deploy - the money command
        ensure_auth
        require_config
        validate_service
        show_context

        # Get deploy time in RFC3339 format
        DEPLOY_TIME=$(gcloud run revisions list --service="$SERVICE" --region="$REGION" --limit=1 --format="value(metadata.creationTimestamp)")
        echo "# Since deploy: $DEPLOY_TIME" >&2

        gcloud logging read "resource.type=cloud_run_revision \
            AND resource.labels.service_name=$SERVICE \
            AND timestamp>=\"$DEPLOY_TIME\"" \
            --limit=100 \
            --format="table(timestamp.date('%H:%M:%S'),severity,textPayload)"
        ;;

    revisions)
        ensure_auth
        require_config
        validate_service
        gcloud run revisions list --service="$SERVICE" --region="$REGION" --format="table(REVISION,ACTIVE,DEPLOYED)"
        ;;

    rev)
        ensure_auth
        require_config
        REV="$2"
        [[ -z "$REV" ]] && {
            echo "Available revisions:"
            gcloud run revisions list --service="$SERVICE" --region="$REGION" --format="value(REVISION)"
            exit 1
        }
        gcloud logging read "resource.type=cloud_run_revision AND resource.labels.revision_name=$REV" \
            --limit=50 \
            --format="table(timestamp.date('%H:%M:%S'),severity,textPayload)"
        ;;

    status)
        # Quick health check
        ensure_auth
        require_config
        validate_service
        gcloud run services describe "$SERVICE" --region="$REGION" --format="json(status.conditions)"
        ;;

    help|--help|-h)
        cat <<EOF
Usage: $0 [command]

Setup:
  init          Setup project/service/account (once)
  config        Show current config (JSON)

Logs:
  errors        Recent errors (default)
  recent        Last 30 lines
  all           Last 200 lines
  tail [sec]    Live tail (default 30s)
  since         Logs since last deploy ← start here after deploy

Revisions:
  revisions     List all revisions
  rev [name]    Logs for specific revision
  status        Service health check
EOF
        ;;

    *)
        echo '{"error":"unknown_command","available":"errors|recent|all|tail|since|revisions|rev|status|config|init"}'
        exit 1
        ;;
esac
