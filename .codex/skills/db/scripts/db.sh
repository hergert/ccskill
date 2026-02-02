#!/bin/bash
set -euo pipefail

# Database helper script
# Usage: db.sh [psql|query "SQL"]

# Find project root (look for .env file)
find_env() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.env" ]] && echo "$dir/.env" && return
        dir="$(dirname "$dir")"
    done
}

# Load DB_URL from .env and convert to psql format
get_psql_url() {
    # Check env var first
    if [[ -n "${DB_URL:-}" ]]; then
        echo "${DB_URL/+asyncpg/}"
        return
    fi

    # Find .env file
    local env_file
    env_file="$(find_env)"
    if [[ -z "$env_file" ]] && [[ -f "$HOME/.env" ]]; then
        env_file="$HOME/.env"
    fi

    if [[ -z "$env_file" ]]; then
        echo '{"error":"no_env_file","fix":"Create .env with DB_URL"}' >&2
        exit 1
    fi

    local db_url
    db_url=$(grep "^DB_URL=" "$env_file" | cut -d= -f2-)
    if [[ -z "$db_url" ]]; then
        echo '{"error":"missing_db_url","fix":"Add DB_URL to .env"}' >&2
        exit 1
    fi
    # Remove +asyncpg from postgresql+asyncpg://
    echo "${db_url/+asyncpg/}"
}

cmd_psql() {
    psql "$(get_psql_url)" "$@"
}

cmd_query() {
    psql "$(get_psql_url)" -c "$1"
}

case "${1:-help}" in
    psql)     shift; cmd_psql "$@" ;;
    query)    shift; cmd_query "$@" ;;
    *)
        echo "Usage: $0 [psql|query \"SQL\"]"
        echo ""
        echo "Commands:"
        echo "  psql          Interactive psql shell"
        echo "  query \"SQL\"   Run SQL query"
        echo ""
        echo "Examples:"
        echo "  $0 psql"
        echo "  $0 query \"SELECT COUNT(*) FROM news\""
        exit 1
        ;;
esac
