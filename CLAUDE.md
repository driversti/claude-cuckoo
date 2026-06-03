# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Cuckoo** is a Claude Code *plugin* (not an app): a durable personal calendar. You schedule a
reminder for a future date/time, and it resurfaces at the start of the next Claude Code session
on or after that date. The whole thing is one Bash script plus a skill and a hook — no runtime, no
dependencies.

## Commands

```bash
bash tests/run.sh                       # full test suite (zero deps; the only check that exists)
claude --plugin-dir /path/to/claude-cuckoo   # load the plugin locally without installing
# inside a Claude session after editing the plugin:
/reload-plugins
```

There is no build, lint, or package step. To run a single behavior in isolation, copy the relevant
block from `tests/run.sh` — each test is a self-contained `new_sandbox` + assert sequence.

## Architecture

Three pieces wire together through the Claude Code plugin contract:

1. **`bin/cuckoo`** — all logic lives here. Subcommands: `check | list | dir | add | remove`
   (`done` is an alias of `remove`) `| reschedule`. The index is parsed/edited entirely with `awk`;
   there is no datastore.
2. **`hooks/hooks.json`** — a `SessionStart` hook (matchers `startup|resume|clear`) that runs
   `cuckoo check`. This runs in the user's shell, *not* the model — that's why an idle session costs
   ~zero tokens. `check` prints due reminders (or nothing) plus an instruction telling the model to
   announce them at the very start of its next reply.
3. **`skills/schedule/SKILL.md`** — the `/cuckoo:schedule` command. This is the model-facing layer:
   it does the natural-language date parsing ("tomorrow", "next friday 9am") and slug generation,
   then calls `bin/cuckoo` for the actual file mutations. **Date parsing is the model's job, not the
   CLI's** — `bin/cuckoo` only ever accepts already-resolved `YYYY-MM-DD` / `YYYY-MM-DDTHH:MM`.

### Data layout (two tiers)

```
~/.claude/cuckoo/        # global tier — personal, cross-project
<repo>/.cuckoo/          # project tier — repo-scoped, ships a .gitignore '*' so reminders never commit
  ├── _index.md          # the hot path: lines of  DUE  STATUS  SLUG  (whitespace-separated, # = comment)
  └── <slug>.md          # the reminder body, read ONLY on the day it fires
```

The split is deliberate: `check` reads only the tiny `_index.md` on every session start; the
full body file is touched only when a reminder is actually due. Preserve this — don't make `check`
read body files.

### Due-time semantics

A reminder fires when its `DUE` token is `<=` now, compared as **plain string prefix** (the index
stores local-time strings; `check` never does real date math). This is why a date-only `2026-06-20`
correctly fires from `2026-06-20T00:00` onward when compared against a datetimed `now` — the
boundary tests in `tests/run.sh` (Task 4) lock this behavior in. It is session-triggered, never a
real-time alarm.

## Conventions & gotchas

- **Env seams are the test contract.** `bin/cuckoo` reads `CUCKOO_HOME` (global dir),
  `CLAUDE_PROJECT_DIR` (project root), and `CUCKOO_NOW_OVERRIDE` (frozen clock). `new_sandbox` in
  `tests/lib.sh` sets all three to a temp tree. Any new time/path dependency must go through a
  similar seam or it won't be testable.
- **Default tier is `global`.** Only use `project` when the task is clearly about the current repo.
- **Slug dedup is exact-match** (`$3==slug` in awk, not regex) — verified by the `my.task` vs
  `my-task` test. Keep comparisons exact so slugs with metachars aren't falsely collapsed.
- **Mutations are atomic via tmpfile** (`remove`/`reschedule` write to `mktemp` then `mv`). Follow
  this pattern for any new index edit.
- Keep the CLI dependency-free POSIX-ish Bash + awk. No jq, no Python, no network.

## Specs

Design rationale and the original build plan live in `docs/superpowers/specs/` and
`docs/superpowers/plans/`. Read them before changing the data model or due-time semantics.
