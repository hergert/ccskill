---
name: db
description: Execute SQL queries against the project database to check data, counts, or state; use when asked to run SQL, inspect tables, verify database state, or debug data issues.
---

# Database Queries

Run commands from the repo root; examples use `.codex/skills/db/scripts/db.sh`.

## Trigger phrases

Use this skill immediately when the user asks:
- "check the database"
- "run this SQL"
- "how many records in X?"
- "what's in the table?"
- "query the database"
- "open psql"
- "verify the data"

## Quick start

```bash
bash .codex/skills/db/scripts/db.sh query "SELECT COUNT(*) FROM news"
bash .codex/skills/db/scripts/db.sh psql  # Interactive shell
```

## Common queries

```sql
-- Check recent records
SELECT id, created_at FROM news ORDER BY created_at DESC LIMIT 10;

-- Check pipeline state
SELECT step, status, COUNT(*) FROM pipeline_runs
GROUP BY step, status ORDER BY step;

-- Find stuck records
SELECT * FROM news WHERE status = 'pending'
AND created_at < NOW() - INTERVAL '1 hour';

-- Check for errors
SELECT id, error_message, created_at FROM news
WHERE error_message IS NOT NULL
ORDER BY created_at DESC LIMIT 20;
```

## ⚠️ Warnings

- **Read-only preferred**: Be careful with UPDATE/DELETE
- **Connection string format**: Supports `asyncpg://` format (auto-converts)
- **No transaction wrapper**: Queries run directly

## Cross-reference

- Data looks wrong → use the PostHog skill for pipeline health
- Missing data → use the Trigger skill for task failures
- Errors in data → use the Sentry skill for related issues

## Configuration

Requires `DB_URL` in `.env`.

Script: `.codex/skills/db/scripts/db.sh`
