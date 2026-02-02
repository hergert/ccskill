---
name: db
description: Execute SQL queries against the project database. Use when user asks to check data, run a query, verify database state, or debug data issues.
---

# Database Queries

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
db.sh query "SELECT COUNT(*) FROM news"
db.sh psql  # Interactive shell
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

- Data looks wrong → `/posthog pipeline` for pipeline health
- Missing data → `/trigger failed` for task failures
- Errors in data → `/sentry errors` for related issues

## Configuration

Requires `DB_URL` in `.env`.

Script: `.claude/skills/db/scripts/db.sh`
