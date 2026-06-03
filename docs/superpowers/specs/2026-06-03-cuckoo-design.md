# Cuckoo 🐦 — Design Spec

**Date:** 2026-06-03
**Status:** Approved design (pre-implementation)

## Goal

A durable, file-based **personal calendar / reminder system for Claude Code**, packaged as an
installable plugin. Date-based reminders "cuckoo" — they resurface at the **start of your next
Claude Code session on or after the due date** — and survive restarts because they live in plain
files, not in an ephemeral session.

One-line pitch: *a tickler file for Claude Code — set a reminder for a future date, and Claude
brings it up the next time you work after that date.*

## Why it exists

In-session schedulers (`CronCreate`) die when the session ends, and their `durable` flag does not
actually persist. There is no built-in way to say "remind me / do this on June 20" and have it
survive across sessions and restarts. Cuckoo fills that gap using the two things that reliably run
every session: a **SessionStart hook** (deterministic trigger) and plain files (durable storage).

## Success criteria

1. A user installs it in ~1 command (`/plugin marketplace add …` + `/plugin install …`) — no manual
   editing of `settings.json` or hand-writing hooks.
2. `/cuckoo:schedule add <when> <what>` creates a durable reminder; it resurfaces automatically on
   the right day with zero further action.
3. **Idle cost ≈ zero tokens.** When nothing is due, a session pays only for one short command
   description — no task content enters context.
4. Works on macOS and Linux (Windows via Git Bash, best-effort).
5. Two tiers: **global** (any project / personal life) and **project-local** (scoped context).

## Core concepts

- **Session-triggered, not a daemon.** Cuckoo cannot push to your phone. A due reminder appears when
  you next *start a Claude Code session* on/after the due date (or, if a time is set, that
  date-time). A time is the *earliest* surfacing moment, not a real-time alarm. (Push notifications
  are the job of the future Google Calendar sync — see *Future*.)
- **Two tiers.**
  - 🌍 **Global** — reminders that aren't tied to a repo (personal, cross-project). Stored under the
    user's home Claude dir.
  - 📂 **Project** — reminders tied to a specific repo, where the surrounding context lives. Stored
    in the project root.
- **Token economy is a first-class requirement.** The heavy content of a task never sits in context
  "just in case"; only the tiny index is consulted (in bash, not in the model), and the full task
  file is read only on the day it fires.

## Architecture

### Plugin package (`claude-cuckoo` repo)

```
claude-cuckoo/
├── .claude-plugin/
│   ├── plugin.json              # identity: name=cuckoo, version, author, license, repo
│   └── marketplace.json         # single-repo marketplace listing the cuckoo plugin
├── hooks/
│   ├── hooks.json               # registers the SessionStart hook
│   └── cuckoo-check.sh          # portable trigger script (the "alarm")
├── skills/
│   └── schedule/
│       └── SKILL.md             # /cuckoo:schedule  (add · list · done · reschedule)
├── README.md
└── LICENSE                      # MIT
```

- `plugin.json` `name` = `cuckoo` → the command is namespaced as **`/cuckoo:schedule`**.
- Hooks ship **inside** the plugin (`hooks/hooks.json`) so installation never touches the user's
  `settings.json`.
- The hook script is referenced via `${CLAUDE_PLUGIN_ROOT}` (the plugin's cached install dir).
- Data files live **outside** the plugin (see below) so plugin updates never wipe a user's
  reminders.

### Data layout (user data, outside the plugin)

```
~/.claude/cuckoo/                      # 🌍 GLOBAL tier
├── _index.md                          # tiny index (the only thing the hook reads)
└── <slug>.md                          # one file per task (the heavy content)

<project-root>/.cuckoo/                 # 📂 PROJECT tier (found via $CLAUDE_PROJECT_DIR)
├── .gitignore                         # contains "*" so personal reminders aren't committed
├── _index.md
└── <slug>.md
```

### `_index.md` format (source of truth, deliberately tiny)

```
# Cuckoo index — one task per line:  DUE  STATUS  SLUG
# DUE = YYYY-MM-DD  OR  YYYY-MM-DDTHH:MM  (local tz, single token, no space)
# STATUS = pending|done · lines starting with # are ignored
2026-06-20        pending  call-dentist
2026-06-21T14:30  pending  standup-prep
```

`DUE` is a single token: a bare date (fires any time that day) or an ISO date-time with a `T`
separator (fires no earlier than that minute). ISO strings sort lexically == chronologically, and a
bare date is a lexical prefix of any time on that day — so the hook compares `DUE` against the
current date-time with one plain string compare, uniformly for both forms. No date library needed.

### `<slug>.md` format (read only when due)

```markdown
# <human-readable title>
- due: YYYY-MM-DD  or  YYYY-MM-DDTHH:MM
- created: YYYY-MM-DD
- tier: global|project

<body — what to remind the user about, or a full task prompt for Claude to execute>
```

The body is free-form: it can be a simple reminder ("dentist at 15:00, bring insurance card") or a
complete instruction prompt for Claude to run (like our Balloon Bonanza final-analysis task).

## Components

### 1. SessionStart hook — `cuckoo-check.sh`

**Registration** (`hooks/hooks.json`): one `SessionStart` entry with combined matcher
`"startup|resume|clear"` and `"async": false`, command
`bash "${CLAUDE_PLUGIN_ROOT}/hooks/cuckoo-check.sh"` (quote the path for safety).

**Behavior:**
1. `now = date +%Y-%m-%dT%H:%M` (local-tz date-time).
2. Scan the **global** index `~/.claude/cuckoo/_index.md`.
3. If `$CLAUDE_PROJECT_DIR` is set, also scan `<project>/.cuckoo/_index.md`.
4. For each line with `status == pending` and `due <= now` (string compare — a bare-date `due` is a
   prefix of any time that day, so it fires from 00:00), emit one line:
   `• [tier] <slug> (due <when>) -> <abs path to slug.md>`.
5. If anything was emitted, print a short header + an **ACTION** line instructing Claude to: read the
   named file(s), surface each task to the user, offer to run it now, and afterward ask whether to
   **delete** or **reschedule**.
6. If nothing is due, print **nothing** and exit 0.

**Contract details:**
- Plain-text stdout only (SessionStart has no JSON output form); stdout is injected as a context
  system-reminder when exit code is 0.
- Always `exit 0` — the hook must never block a session, even on malformed input.
- Reads only `_index.md` files (never the `<slug>.md` bodies) — this is what keeps idle cost at ~0.
- Portable: only `$HOME`, `$CLAUDE_PROJECT_DIR`, `date`, `awk`, `sed`. No hardcoded user paths.
- A `CUCKOO_NOW_OVERRIDE` env var (a `YYYY-MM-DDTHH:MM` string) lets tests simulate the current date-time.

### 2. `/cuckoo:schedule` skill (`skills/schedule/SKILL.md`)

A **single** command with a subcommand as its first argument (one command = one always-loaded
description = minimal idle context). Frontmatter: short `description`, `argument-hint:
"<add|list|done|reschedule> …"`. User- and model-invocable (so "remind me tomorrow to X" can route
here), but tuned to trigger only on scheduling intent.

Subcommands:

- **`add <when> <what>`** `[--global|--project]`
  - Claude resolves `<when>` (e.g. `tomorrow`, `next friday 9am`, `2026-07-01`, `today 14:30`) to
    `YYYY-MM-DD` (date-only) or `YYYY-MM-DDTHH:MM` (when a time of day is given), using the session's
    current date-time + local tz.
  - Generates a kebab-case `<slug>` from `<what>` (deduped with a numeric suffix if it already
    exists).
  - Tier: `--global`/`--project` flag wins; default **global**; if `--project`, requires being in a
    project (uses `$CLAUDE_PROJECT_DIR`, creating `.cuckoo/` + its `.gitignore` on first use).
  - Writes `<slug>.md` (title/due/created/tier + body) and appends the index line. Confirms with the
    resolved date and tier.
- **`list`** — reads global + (if in a project) project indexes; prints pending tasks sorted by due
  date-time, showing the time when present, with a relative "in N days" / "today" / "overdue" label.
- **`done <slug>`** (alias `delete`) — removes the `<slug>.md` file and its index line.
- **`reschedule <slug> <when>`** — resolves the new date (with optional time) and updates the index
  line in place.

## Data flow

```
add → write <slug>.md + index line                         (durable on disk)
         │
   …time passes, sessions come and go (hook silent)…
         │
session start on/after due → hook reads _index.md → prints due task(s) → Claude reads <slug>.md,
   surfaces to user, offers to run → after running, asks: delete or reschedule
```

## Token economy (explicit — a hard requirement)

| Session state | What reaches the model's context | Cost |
|---|---|---|
| Nothing due | hook runs in bash, reads only `_index.md`, prints nothing | one short `/cuckoo:schedule` description (~1 line) |
| Task(s) due | hook prints `slug + path + short action` | a few lines |
| Running a due task | Claude reads only that one `<slug>.md` | just that file |

The heavy task body is quarantined in per-task files and never preloaded. The index stays tiny by
construction (3 fields/line).

## Distribution & installation

Single repo doubles as marketplace + plugin.

- `.claude-plugin/marketplace.json` — marketplace `name` + one plugin entry pointing at the repo-root
  plugin (relative source). Relative sources resolve when the marketplace is added via GitHub.
- User installs with:
  ```
  /plugin marketplace add driversti/claude-cuckoo
  /plugin install cuckoo@<marketplace-name>
  ```
- `version` set in `plugin.json` (single source of truth) so users get updates only on version bumps.

## Date, time & timezone handling

- Dates/times are in the user's **local** timezone. `DUE` is stored as `YYYY-MM-DD` (date-only) or
  `YYYY-MM-DDTHH:MM`.
- The hook uses `date +%Y-%m-%dT%H:%M` (local) for "now"; the skill asks Claude to resolve a
  natural-language `<when>` to an absolute local date (and time, when given) — no date library, no
  external calls.
- **Time-of-day semantics:** a time sets the *earliest* moment a reminder may surface; it is NOT a
  real-time alarm. A timed task appears at the first session start at/after that minute. True
  minute-precise, device-level alarms are the job of the future Google Calendar sync.

## Edge cases & error handling

- Missing/empty index → hook prints nothing (no error).
- Malformed index line (fewer than 3 fields) → skipped.
- Overdue tasks (due < today, still pending) keep surfacing every session until done/rescheduled —
  intentional (you didn't deal with it yet).
- Duplicate slug on `add` → append numeric suffix.
- `--project` outside a project (no `$CLAUDE_PROJECT_DIR`) → the skill explains and offers global.
- Hook must never error a session: `exit 0` always; guard all file reads.

## Cross-platform

- Hook invoked as `bash ${CLAUDE_PLUGIN_ROOT}/hooks/cuckoo-check.sh` → no executable bit needed.
- Uses POSIX-ish `awk`/`sed`/`date +%F`, available on macOS, Linux, and Windows Git Bash.
- Keep the script free of unconditional profile `echo`s; it controls its own output.

## Security & privacy

- **No network.** Everything is local files. No telemetry.
- **No edits to the user's `settings.json`** — the hook is owned by the plugin.
- Project reminders live in `<project>/.cuckoo/` with a bundled `.gitignore` (`*`) so personal
  reminders are never accidentally committed.
- Task bodies may contain personal notes — they stay on the user's machine.

## Testing strategy

- **Hook unit tests** (bash): feed crafted `_index.md` fixtures + `CUCKOO_NOW_OVERRIDE`; assert
  silence when nothing due, correct surfacing when due (both date-only and timed `DUE`, incl. the
  "timed task not before its minute" boundary), correct tier labels, project-tier resolution via a
  fake `$CLAUDE_PROJECT_DIR`, graceful handling of missing/malformed files.
- **Skill behavior** documented with worked examples in README; manual acceptance checklist for
  add/list/done/reschedule across both tiers.
- **Install smoke test:** add the marketplace, install, start a session with a due fixture, confirm
  the reminder surfaces.

## Out of scope (v1) / Future

- **Google Calendar two-way sync** (the path to real phone push notifications). Designed-for, not
  built: the file model maps cleanly to calendar events later.
- **In-session precision timer (best-effort)** — when a timed task is due soon and a session is
  already open, arm a one-shot in-session timer (`CronCreate`) that fires at the exact minute, so the
  reminder surfaces on time instead of waiting for the next session start. Layered *on top of* the
  durable file, which stays the guarantee: if the session closes first, the file still surfaces the
  task next start (graceful degradation — worst case is v1 behavior, best case is exact-time). The
  `HH:MM` data model already enables this; no format change needed. Open design points: it only works
  while a session is open and idle (not a device push — that's Calendar's job); it needs de-dup so a
  resume/restart doesn't double-arm; and arming all of the day's remaining timed tasks at session
  start is likely simpler and more correct than a fixed look-ahead window (a window can miss tasks
  that cross into range mid-session, and stale one-shot crons harmlessly die with the session).
- **Recurring reminders** (daily/weekly/cron) — needs next-occurrence logic and a richer index.
- **Snooze**, categories/tags, a `done/` archive for history.

## License

MIT.

## Resolved decisions (verified against code.claude.com/docs + real installed plugins)

1. **Marketplace source = `"./"`.** Single-plugin repo: the plugin lives at the repo root
   (`./.claude-plugin/plugin.json`), and `./.claude-plugin/marketplace.json` lists it with
   `"source": "./"`. Confirmed by the superpowers plugin's own self-marketplace.
2. **SessionStart hook:** one entry in `hooks/hooks.json` with combined matcher
   `"startup|resume|clear"` and `"async": false`; command
   `bash "${CLAUDE_PLUGIN_ROOT}/hooks/cuckoo-check.sh"`. Matchers combine with `|` (no separate
   entries needed).
3. **The command is a Skill, not a flat command.** `commands/` is legacy ("use `skills/` for new
   plugins"). File: `skills/schedule/SKILL.md`. Plugin skills are **always namespaced**, so it is
   invoked as **`/cuckoo:schedule`** (`name: cuckoo` in plugin.json sets the prefix). A single skill
   takes the subcommand as the first argument via `$ARGUMENTS` (e.g.
   `/cuckoo:schedule add tomorrow 9am "..."`). Components at default locations are auto-discovered —
   declaring their paths in plugin.json is optional.
4. **Migration is a separate post-v1 task.** Once Cuckoo is installable, move the personal ad-hoc
   scheduler (`~/.claude/scheduled/` + the Balloon Bonanza task + the hand-added global
   `settings.json` hook) onto Cuckoo, then remove the ad-hoc hook to avoid double-surfacing. Tracked
   outside this spec.

**Dev/test workflow:** build and iterate locally with `claude --plugin-dir ./claude-cuckoo` (no
publish needed); `/reload-plugins` picks up changes. Publish to GitHub + marketplace only when ready.
```
