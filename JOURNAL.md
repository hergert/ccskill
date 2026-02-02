# Journal

> Only write what would cost time to rediscover. No fluff.

---

## 2026-02-02

**Context:** Building CLI wrappers for agentic coding - reduce errors when agents call external APIs.

**Explored:**
- `~/Spaces/searchceergo/scribe` - has `posthog.sh`, `sentry-stats.sh`, `trigger.sh`, `cloudrun-logs.sh`
- `~/Spaces/reper/resper-api` - has `cloudrun-logs.sh` (nearly identical to scribe's)

**Patterns worth keeping:**
- JSON output from all wrappers (agents parse it)
- Load from `.env` when env vars missing
- Error messages include fix suggestions
- Justfile as facade, scripts do the work

**Decision:** Journal should be compressed learnings, not a log. High value per line.

**Done:** Copied shell wrappers from scribe → `./scripts/`
- `cloudrun-logs.sh`, `posthog.sh`, `sentry-stats.sh`, `trigger.sh`, `db.sh`

**Key insight:** These aren't just curl wrappers - they're guardrails that prevent agents from yak-shaving.

**Error prevention patterns found:**
- Wrong key type detected early (phc_ vs phx_)
- Missing deps caught before work starts
- Graceful .env fallback
- Input normalization (auto-prefix run_id)
- Config persistence (don't re-init every time)

**Error recovery patterns found:**
- Every error includes `fix` field
- Unknown commands list available ones
- Missing args show usage
- Context shown so you know what you're hitting

**Problem:** Hardcoded project values throughout:
- `PROJECT_ID="189513"` in posthog.sh
- `ORG="searchergo"`, `PROJECT="scribe"` in sentry-stats.sh
- Need config per-project or generalization

**Open:** What to do next - generalize for multi-project use?

---

## 2026-02-02 (continued)

**Explored:** OpenClaw repo (`tmp/openclaw/`) - large codebase with CLI tools and skills system

**Key discovery - Skills system:**
- Skills = modular packages with metadata for triggering
- Three-level loading: metadata (always) → SKILL.md (on trigger) → resources (as needed)
- Dependency gating: `requires.bins`, `requires.env`, `requires.config`
- Description field drives when Claude uses a skill
- Progressive disclosure keeps context lean

**Patterns from their scripts (77 scripts):**
- Same as ours: JSON output, env var fallbacks, error + fix messages
- Different: `--json` flag pattern for optional structured output
- Different: secret masking (`first6...last6` reveal)
- Different: no external arg parsers - all built-in

**From AGENTS.md:**
- Multi-agent safety: no git stash, no branch switching unless requested
- Tool schema constraints: avoid Union types, anyOf/oneOf
- "Verify in code; do not guess"

**Key insight:** Our scripts are standalone tools with hardcoded values. OpenClaw skills are discoverable modules with metadata-driven triggering. Different philosophy - theirs optimizes for context efficiency and discoverability.

**Question:** Should we adopt a skills-like approach, or keep scripts simple and just generalize them?

---

## 2026-02-02 (continued)

**Discovery: Claude Code has native skills system**

Researched Claude Code changelog and docs. Skills are exactly what we need:

**How skills work:**
- `~/.claude/skills/<name>/SKILL.md` - personal, all projects
- `.claude/skills/<name>/SKILL.md` - project-specific
- YAML frontmatter + markdown body
- Description field = trigger logic (Claude auto-loads when conversation matches)
- Can bundle scripts in `scripts/` subdirectory

**Key frontmatter fields:**
- `description` - CRITICAL: determines when Claude uses the skill
- `allowed-tools` - restrict what tools skill can use
- `disable-model-invocation: true` - manual only (you invoke with /name)
- `user-invocable: false` - Claude only (background knowledge)
- `context: fork` - run in isolated subagent

**Progressive disclosure:**
1. Description always in context (for triggering)
2. Full SKILL.md loads when triggered
3. Reference files load when needed
4. Scripts execute without loading into context

**Decision:** Use Claude Code native skills instead of inventing our own system.

**Plan created:** Convert 5 scripts into Claude Code skills
- Each skill: SKILL.md (when/how/workflow) + scripts/ subdirectory
- Skills go in `~/.claude/skills/` for cross-project use
- Key: description triggers auto-loading, body teaches workflow
- Cross-references between skills (posthog ↔ sentry ↔ trigger ↔ cloudrun-logs)

---

## 2026-02-02 (continued)

**Implemented: CLI tools → Claude Code skills**

Created `.claude/skills/` with 5 skills:
- `posthog/` - LLM observability, pipeline health, dashboard debugging
- `sentry/` - errors, spans, traces, performance
- `trigger/` - Trigger.dev task runs and failures
- `cloudrun-logs/` - post-deploy debugging, error scanning
- `db/` - quick SQL queries

**Structure per skill:**
```
.claude/skills/<name>/
├── SKILL.md          # Frontmatter + when/how/workflow docs
└── scripts/
    └── <name>.sh     # Actual tool
```

**Script changes for location-agnosticism:**

Added `find_env()` to all scripts:
```bash
find_env() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/.env" ]] && echo "$dir/.env" && return
        dir="$(dirname "$dir")"
    done
}
```

Walks up from cwd looking for `.env`. Falls back to `$HOME/.env`.

**Made hardcoded values configurable:**
- `PROJECT_ID="${POSTHOG_PROJECT_ID:-189513}"`
- `ORG="${SENTRY_ORG:-searchergo}"`
- etc.

Defaults still work, but can override per-environment.

**Fixed: help without API keys**

Problem: `set -euo pipefail` + missing key = crash before help shows.

Solution: Handle help case early, before key validation:
```bash
case "${1:-help}" in
    help|--help|-h) show_help; exit 0 ;;
esac
# Now require API key...
```

**SKILL.md anatomy:**
```yaml
---
name: posthog
description: Query PostHog for LLM observability...
---
## When to use
## Quick start
## Commands
## Workflow: <specific task>
## Interpreting results
## Configuration
```

Description = what triggers Claude to load the skill. Body = instructions once loaded.

**Key insight:** Workflow sections are high-value. Not just "here are commands" but "here's how to debug slow LLM calls step by step." Claude follows workflows.

**Deleted:** `scripts/` directory (empty after migration)

---

## 2026-02-02 (continued)

**Self-review of skills implementation**

Stopped to critically assess quality. Found issues:

**Problem 1: Verbose paths in SKILL.md**
```bash
# Before - cluttered, breaks if not in project root
.claude/skills/posthog/scripts/posthog.sh llm 1

# After - Claude can find it
posthog.sh llm 1
```
Added "Script location:" hint as fallback. Trust Claude to resolve paths.

**Problem 2: Skills load at session start**

Created skills mid-session → they won't appear until restart. To verify skills work:
- Start new session in project directory
- Type `/` and check menu for skill names
- Or ask "What skills are available?"
- Or run `/context` to see loaded skills

**Researched: How Claude Code skills actually work**

Discovery locations (priority order):
1. Enterprise managed settings
2. `~/.claude/skills/` (personal, all projects)
3. `.claude/skills/` (project-specific)
4. Nested `.claude/skills/` in subdirectories (monorepo support)

Loading behavior:
- Descriptions always in context (for triggering decisions)
- Full SKILL.md loads only when invoked
- Character budget: 15,000 chars default (`SLASH_COMMAND_TOOL_CHAR_BUDGET` to increase)

**Frontmatter fields discovered:**
```yaml
---
name: skill-name              # Optional, defaults to directory name
description: When to use...   # Critical - drives auto-invocation
argument-hint: [issue-number] # Shows in autocomplete
disable-model-invocation: true  # Manual only (for /deploy, /commit)
user-invocable: false         # Hidden from menu, Claude-only
allowed-tools: Read, Grep     # Tools without permission prompts
context: fork                 # Run in isolated subagent
agent: Explore                # Which subagent type
---
```

**Dynamic injection syntax:**
```yaml
PR diff: !`gh pr diff`
```
The `!`command`` runs shell and injects output into skill context. Didn't use this but worth knowing.

**Invocation methods:**
- `/skill-name args` - direct user invocation
- Automatic - Claude reads descriptions, decides relevance
- Slash menu - type `/` to see all

**Key insight:** Description field is everything. Claude uses it to decide when to auto-invoke. Be specific about triggers, not just what it does.

**Deeper finding: No algorithmic routing**

Skills have no embeddings, classifiers, or pattern matching. The mechanism is simple:
1. Skill metadata (name + description) injected into system prompt
2. Claude's LLM reasoning decides when to invoke

That's it. No magic. Just text in context.

**Discovery locations (corrected):**
- `~/.config/claude/skills/` (user settings)
- `.claude/skills/` (project)
- Plugin-provided skills
- Built-in skills

**Progressive disclosure confirmed:**
- Metadata loaded at startup → included in system prompt
- Many skills = no context penalty (just names + descriptions)
- Full SKILL.md loads only when triggered

**Verification methods:**
- `/skills` - list available skills
- Ask "what skills do you have available?"
- `/skill-name` - explicit invocation
- Describe task matching description - implicit invocation

**Learning curve warning:**
> "The first few skills people create tend to be too broad. After seeing what actually gets surfaced and what doesn't, authors learn to be specific."

Our descriptions might be too broad. Example:
```yaml
# Maybe too broad
description: Query PostHog for LLM observability and pipeline health.

# More specific triggers
description: Query PostHog for LLM observability. Use when user asks about LLM costs, token usage, latency, slow calls, or pipeline step failures.
```

**TODO:** Test skills in fresh session, observe what triggers them, refine descriptions based on actual behavior.

---

## 2026-02-02 (continued)

**Studied OpenClaw skill patterns**

Cloned `github.com/openclaw/openclaw`, examined their SKILL.md files:
- `coding-agent` (285 lines) - complex, multi-tool orchestration
- `summarize` (88 lines) - compact, focused
- `session-logs` (116 lines) - lots of copy-paste examples
- `model-usage` (70 lines) - references external docs

**Key pattern: Trigger phrases**

OpenClaw skills have explicit "When to use (trigger phrases)" sections:

```markdown
## Trigger phrases

Use this skill immediately when the user asks:
- "how much did LLM cost today?"
- "what's this link about?"
- "transcribe this YouTube"
```

This is different from our original approach which was command-oriented ("Investigating LLM costs → `llm [hours]`"). Theirs is phrase-oriented - actual words users say.

**What great skills have:**

1. **Trigger phrases** - user questions, not command mappings
2. **Quick start** - immediate copy-paste commands
3. **Workflows** - step-by-step guides for specific tasks
4. **Interpreting results** - tables explaining what signals mean
5. **⚠️ Warnings** - gotchas that will bite you
6. **Cross-references** - when to use other skills
7. **References** - point to --help or docs for details

**What great skills DON'T have:**

- Exhaustive command lists (that's --help)
- Obvious explanations
- Duplicated information

**Applied to our skills:**

Rewrote all 5 SKILL.md files with this structure. Final sizes: 62-82 lines each.

Before: command-oriented, duplicated --help
After: phrase-oriented, workflow-focused, with warnings

**Principle:** The description triggers the skill. The trigger phrases section reinforces it. The workflows teach what to do once triggered. Everything else is reference.

---
