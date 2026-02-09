# ccskill

Manage and distribute Claude Code / Codex skills across projects. Skills are agent-friendly CLI wrappers that produce JSON output, load config from `.env`, and include error messages with fix suggestions.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/hergert/ccskill/main/install.sh | bash
```

Requires: `git`, `gum` (for interactive UI), `jq` (for skills that query APIs).

## Usage

```bash
ccskill list              # available skills
ccskill add posthog       # copy skill into current project
ccskill status            # check for updates
ccskill update posthog    # diff + replace
ccskill remove posthog    # remove from project
ccskill sync              # pull latest from remote
ccskill info posthog      # view SKILL.md
```

Use `--yes` / `-y` to skip confirmations.

## Skills

| Skill | What it does | Key env vars |
|-------|-------------|-------------|
| **posthog** | LLM cost/latency, pipeline health, dashboard debugging | `POSTHOG_PERSONAL_API_KEY`, `POSTHOG_PROJECT_ID` |
| **sentry** | Errors, traces, spans, endpoint performance | `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_PROJECT_ID` |
| **trigger** | Trigger.dev task runs and failures | `TRIGGER_SECRET_KEY` |
| **cloudrun-logs** | Cloud Run logs, post-deploy debugging | `gcloud` CLI auth |
| **db** | SQL queries via psql | `DB_URL` |
| **playwright** | Browser automation, screenshots, UI validation | `bun` runtime |

All config is read from environment variables or `.env` (searched upward from cwd).

## How skills work

Skills live in `.claude/skills/` (or `.codex/skills/`). Each has a `SKILL.md` with YAML frontmatter that tells the agent when to use it, and a `scripts/` directory with the actual tools.

```
.claude/skills/posthog/
├── SKILL.md
└── scripts/
    └── posthog.sh
```

The agent reads skill descriptions at session start and auto-invokes them when the conversation matches.

## .env example

```
POSTHOG_PERSONAL_API_KEY=phx_...
POSTHOG_PROJECT_ID=12345
SENTRY_AUTH_TOKEN=sntrys_...
SENTRY_ORG=my-org
SENTRY_PROJECT=my-project
SENTRY_PROJECT_ID=1234567890
TRIGGER_SECRET_KEY=tr_...
DB_URL=postgresql://...
```
