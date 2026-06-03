# Cuckoo 🐦 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `cuckoo` — an installable Claude Code plugin that gives durable, file-based personal
reminders (global + per-project tiers) which resurface at the start of the next session on/after a
due date (optionally date-time), at near-zero idle token cost.

**Architecture:** A single portable bash CLI (`bin/cuckoo`) owns all deterministic logic
(index/date/dedup/query). A SessionStart hook runs `cuckoo check` and prints due tasks (or nothing).
A namespaced skill `/cuckoo:schedule` drives `add|list|done|reschedule`, with Claude resolving
natural-language dates and writing each task's body file. Data lives outside the plugin
(`~/.claude/cuckoo/`, `<project>/.cuckoo/`) so updates never wipe reminders.

**Tech Stack:** Bash (POSIX-ish: `awk`/`sed`/`date`), JSON manifests, a zero-dependency bash test
runner, Claude Code plugin packaging (`plugin.json` + `marketplace.json` + `hooks/hooks.json` +
`skills/`).

**Spec:** `docs/superpowers/specs/2026-06-03-cuckoo-design.md` (read it first).

---

## File structure

```
claude-cuckoo/
├── .claude-plugin/
│   ├── plugin.json          # identity; name=cuckoo → /cuckoo:schedule
│   └── marketplace.json     # single-plugin marketplace, source "./"
├── bin/
│   └── cuckoo               # the CLI: check|list|dir|add|remove|reschedule  (chmod +x)
├── hooks/
│   └── hooks.json           # SessionStart → bash "${CLAUDE_PLUGIN_ROOT}/bin/cuckoo" check
├── skills/
│   └── schedule/
│       └── SKILL.md         # /cuckoo:schedule (add/list/done/reschedule)
├── tests/
│   ├── lib.sh               # assert helpers + sandbox
│   └── run.sh               # zero-dependency test suite (bash tests/run.sh)
├── README.md
├── LICENSE                  # MIT
├── .gitignore               # exists (.DS_Store, .idea/, .cuckoo/, ...)
└── docs/superpowers/...     # spec + this plan
```

**Conventions used by `bin/cuckoo` (also the test seams):**
- `CUCKOO_NOW_OVERRIDE` — `YYYY-MM-DDTHH:MM` to fake "now" (tests).
- `CUCKOO_HOME` — overrides the global dir (default `$HOME/.claude/cuckoo`) (tests/sandbox).
- Project dir = `${CLAUDE_PROJECT_DIR:-$PWD}/.cuckoo`.
- Index line: `DUE  STATUS  SLUG` where `DUE` = `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM` (single token).

---

## Task 1: Plugin manifests, LICENSE, README stub

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `LICENSE`
- Create: `README.md` (stub; expanded in Task 11)

- [ ] **Step 1: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "cuckoo",
  "description": "Durable personal calendar for Claude Code — date/time reminders that resurface at your next session on/after the due date.",
  "version": "0.1.0",
  "author": { "name": "Yurii Chekhotskyi" },
  "homepage": "https://github.com/driversti/claude-cuckoo",
  "repository": "https://github.com/driversti/claude-cuckoo",
  "license": "MIT",
  "keywords": ["reminders", "calendar", "scheduler", "tickler", "productivity", "hooks"]
}
```

- [ ] **Step 2: Write `.claude-plugin/marketplace.json`**

```json
{
  "name": "cuckoo",
  "description": "Cuckoo — durable personal calendar for Claude Code",
  "owner": { "name": "Yurii Chekhotskyi" },
  "plugins": [
    {
      "name": "cuckoo",
      "source": "./",
      "description": "Date/time reminders that resurface at your next session on/after the due date."
    }
  ]
}
```

- [ ] **Step 3: Write `LICENSE`** — standard MIT text, first line:
  `MIT License` … `Copyright (c) 2026 Yurii Chekhotskyi` … (full standard MIT body).

- [ ] **Step 4: Write `README.md` stub**

```markdown
# Cuckoo 🐦

Durable personal calendar for Claude Code. Reminders resurface at the start of your next session
on/after their due date. (Full docs added in Task 11.)
```

- [ ] **Step 5: Verify the JSON parses**

Run: `python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); json.load(open('.claude-plugin/marketplace.json')); print('ok')"`
Expected: `ok`

- [ ] **Step 6: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat: plugin manifests, LICENSE, README stub"
```

---

## Task 2: Test harness + `cuckoo` skeleton + `check` (empty → silent)

**Files:**
- Create: `tests/lib.sh`
- Create: `tests/run.sh`
- Create: `bin/cuckoo`

- [ ] **Step 1: Write the failing test harness `tests/lib.sh`**

```bash
# tests/lib.sh — zero-dependency assert helpers + sandbox.
TESTS_RUN=0; TESTS_FAILED=0
CUCKOO_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/cuckoo"
cuckoo() { bash "$CUCKOO_BIN" "$@"; }

# sandbox: isolated global + project dirs in a temp tree; sets the env seams.
new_sandbox() {
  SANDBOX="$(mktemp -d)"
  export CUCKOO_HOME="$SANDBOX/global"
  export CLAUDE_PROJECT_DIR="$SANDBOX/project"
  mkdir -p "$CUCKOO_HOME" "$CLAUDE_PROJECT_DIR"
  unset CUCKOO_NOW_OVERRIDE
}

assert_eq()       { TESTS_RUN=$((TESTS_RUN+1)); [ "$1" = "$2" ] || { TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s\n  expected:[%s]\n  actual:  [%s]\n' "$3" "$1" "$2"; }; }
assert_empty()    { TESTS_RUN=$((TESTS_RUN+1)); [ -z "$1" ] || { TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s (expected empty, got [%s])\n' "$2" "$1"; }; }
assert_contains() { TESTS_RUN=$((TESTS_RUN+1)); case "$1" in *"$2"*) ;; *) TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s (missing [%s])\n' "$3" "$2";; esac; }
assert_missing()  { TESTS_RUN=$((TESTS_RUN+1)); case "$1" in *"$2"*) TESTS_FAILED=$((TESTS_FAILED+1)); printf 'FAIL: %s (should NOT contain [%s])\n' "$3" "$2";; *) ;; esac; }
finish() { printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"; [ "$TESTS_FAILED" -eq 0 ]; }
```

- [ ] **Step 2: Write the first failing test in `tests/run.sh`**

```bash
#!/usr/bin/env bash
# tests/run.sh — run with: bash tests/run.sh
. "$(dirname "$0")/lib.sh"

# check: nothing scheduled → silent
new_sandbox
out="$(cuckoo check)"
assert_empty "$out" "check: empty sandbox is silent"

finish
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (no `bin/cuckoo` yet → `cuckoo` errors / non-empty stderr).

- [ ] **Step 4: Create `bin/cuckoo` with dispatch + minimal `check`**

```bash
#!/usr/bin/env bash
# cuckoo — durable personal calendar for Claude Code.
set -uo pipefail

cuckoo_now()   { printf '%s' "${CUCKOO_NOW_OVERRIDE:-$(date +%Y-%m-%dT%H:%M)}"; }
global_dir()   { printf '%s' "${CUCKOO_HOME:-$HOME/.claude/cuckoo}"; }
project_dir()  { printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}/.cuckoo"; }
tier_dir()     { case "$1" in global) global_dir;; project) project_dir;; *) return 1;; esac; }

cmd_check() { return 0; }   # filled in Task 3

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    check) cmd_check "$@" ;;
    *) echo "usage: cuckoo <check|list|dir|add|remove|reschedule>" >&2; return 2 ;;
  esac
}
main "$@"
```

- [ ] **Step 5: Make it executable**

Run: `chmod +x /Users/driversti/Projects/claude-cuckoo/bin/cuckoo`

- [ ] **Step 6: Run tests to confirm they pass**

Run: `bash tests/run.sh`
Expected: `1 run, 0 failed`

- [ ] **Step 7: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "test: harness + cuckoo skeleton (check is silent when empty)"
```

---

## Task 3: `check` — global tier, date-only due

**Files:** Modify `bin/cuckoo`, `tests/run.sh`.

- [ ] **Step 1: Add failing tests** (append before `finish` in `tests/run.sh`)

```bash
# check: past-due date-only global task surfaces
new_sandbox
export CUCKOO_NOW_OVERRIDE="2026-06-20T09:00"
printf '2026-06-20  pending  call-dentist\n' > "$CUCKOO_HOME/_index.md"
out="$(cuckoo check)"
assert_contains "$out" "[global] call-dentist (due 2026-06-20)" "check: surfaces due global task"
assert_contains "$out" "ACTION:" "check: prints action line"

# check: future date-only task stays silent
new_sandbox
export CUCKOO_NOW_OVERRIDE="2026-06-20T09:00"
printf '2026-06-25  pending  future-thing\n' > "$CUCKOO_HOME/_index.md"
assert_empty "$(cuckoo check)" "check: future task silent"

# check: done task never surfaces
new_sandbox
export CUCKOO_NOW_OVERRIDE="2026-06-20T09:00"
printf '2026-06-19  done  already\n' > "$CUCKOO_HOME/_index.md"
assert_empty "$(cuckoo check)" "check: done task silent"
```

- [ ] **Step 2: Run → expect new failures.** Run: `bash tests/run.sh`

- [ ] **Step 3: Implement `scan_index` + `cmd_check` (global only)** — replace the stub `cmd_check`:

```bash
scan_index() {  # $1 index  $2 label  $3 dir  $4 now
  local index="$1" label="$2" dir="$3" now="$4"
  [ -f "$index" ] || return 0
  awk -v now="$now" -v label="$label" -v dir="$dir" '
    /^[[:space:]]*#/ { next } /^[[:space:]]*$/ { next }
    NF>=3 && $2=="pending" && $1<=now {
      printf "  • [%s] %s (due %s) -> %s/%s.md\n", label, $3, $1, dir, $3
    }' "$index"
}

cmd_check() {
  local now out
  now="$(cuckoo_now)"
  out="$(scan_index "$(global_dir)/_index.md" global "$(global_dir)" "$now")"
  if [ -n "$out" ]; then
    printf '%s\n' \
      "⏰ CUCKOO — scheduled task(s) due" \
      "$out" \
      "ACTION: read the named file(s), surface each task to the user, and offer to run it now. After running, ask whether to mark it done or reschedule it."
  fi
  return 0
}
```

- [ ] **Step 4: Run → pass.** Run: `bash tests/run.sh` → `N run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat(check): surface due date-only tasks (global tier)"
```

---

## Task 4: `check` — timed (HH:MM) due, with boundary

**Files:** Modify `tests/run.sh` only (the comparison already uses a datetime `now`; this task proves
the date-only-prefix property and the timed boundary, and locks them with tests).

- [ ] **Step 1: Add failing/locking tests**

```bash
# timed task: not before its minute
new_sandbox
printf '2026-06-20T14:30  pending  standup\n' > "$CUCKOO_HOME/_index.md"
export CUCKOO_NOW_OVERRIDE="2026-06-20T14:29"; assert_empty   "$(cuckoo check)" "timed: silent at 14:29"
export CUCKOO_NOW_OVERRIDE="2026-06-20T14:30"; assert_contains "$(cuckoo check)" "standup" "timed: fires at 14:30"
export CUCKOO_NOW_OVERRIDE="2026-06-20T14:31"; assert_contains "$(cuckoo check)" "standup" "timed: fires at 14:31"

# date-only task fires from 00:00 (prefix property), even compared to a datetime now
new_sandbox
printf '2026-06-20  pending  allday\n' > "$CUCKOO_HOME/_index.md"
export CUCKOO_NOW_OVERRIDE="2026-06-20T00:01"; assert_contains "$(cuckoo check)" "allday" "date-only: fires from 00:01"
export CUCKOO_NOW_OVERRIDE="2026-06-19T23:59"; assert_empty   "$(cuckoo check)" "date-only: silent day before"
```

- [ ] **Step 2: Run.** Expected: PASS already (the `$1<=now` string compare + datetime `now` handle
  both forms — a bare date is a lexical prefix of any time that day). If any fail, the bug is in
  `cuckoo_now` (must be `%Y-%m-%dT%H:%M`, not `%F`). Fix there.

- [ ] **Step 3: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "test(check): lock HH:MM boundary + date-only prefix semantics"
```

---

## Task 5: `check` — project tier + robustness

**Files:** Modify `bin/cuckoo`, `tests/run.sh`.

- [ ] **Step 1: Add failing tests**

```bash
# project tier surfaces with [project]
new_sandbox
export CUCKOO_NOW_OVERRIDE="2026-06-20T09:00"
mkdir -p "$CLAUDE_PROJECT_DIR/.cuckoo"
printf '2026-06-20  pending  ship-release\n' > "$CLAUDE_PROJECT_DIR/.cuckoo/_index.md"
out="$(cuckoo check)"
assert_contains "$out" "[project] ship-release" "check: project tier surfaces"

# both tiers at once
printf '2026-06-20  pending  call-dentist\n' > "$CUCKOO_HOME/_index.md"
out="$(cuckoo check)"
assert_contains "$out" "[global] call-dentist" "check: global+project both listed"
assert_contains "$out" "[project] ship-release" "check: global+project both listed"

# malformed/comment lines ignored; missing files silent
new_sandbox
export CUCKOO_NOW_OVERRIDE="2026-06-20T09:00"
printf '# a comment\ngarbage line\n2026-06-20 pending ok-task\n' > "$CUCKOO_HOME/_index.md"
out="$(cuckoo check)"
assert_contains "$out" "ok-task" "check: valid line surfaces"
assert_missing  "$out" "garbage" "check: malformed line skipped"
```

- [ ] **Step 2: Run → fail** (project tier not scanned yet).

- [ ] **Step 3: Extend `cmd_check` to also scan the project tier** — replace `cmd_check`:

```bash
cmd_check() {
  local now out pdir pout
  now="$(cuckoo_now)"
  out="$(scan_index "$(global_dir)/_index.md" global "$(global_dir)" "$now")"
  pdir="$(project_dir)"
  pout="$(scan_index "$pdir/_index.md" project "$pdir" "$now")"
  if [ -n "$pout" ]; then [ -n "$out" ] && out+=$'\n'; out+="$pout"; fi
  if [ -n "$out" ]; then
    printf '%s\n' \
      "⏰ CUCKOO — scheduled task(s) due" \
      "$out" \
      "ACTION: read the named file(s), surface each task to the user, and offer to run it now. After running, ask whether to mark it done or reschedule it."
  fi
  return 0
}
```

- [ ] **Step 4: Run → pass. Step 5: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat(check): project tier + malformed-line robustness"
```

---

## Task 6: `dir` + `add` (with slug dedup)

**Files:** Modify `bin/cuckoo`, `tests/run.sh`.

- [ ] **Step 1: Add failing tests**

```bash
# dir global creates the dir and prints it
new_sandbox
d="$(cuckoo dir global)"; assert_eq "$CUCKOO_HOME" "$d" "dir global path"
[ -d "$CUCKOO_HOME" ]; assert_eq "0" "$?" "dir global created"

# dir project creates dir + .gitignore '*'
d="$(cuckoo dir project)"; assert_eq "$CLAUDE_PROJECT_DIR/.cuckoo" "$d" "dir project path"
assert_eq "*" "$(cat "$CLAUDE_PROJECT_DIR/.cuckoo/.gitignore")" "dir project gitignores all"

# add appends an index line and echoes the slug
new_sandbox
s="$(cuckoo add global 2026-06-20 call-dentist)"; assert_eq "call-dentist" "$s" "add echoes slug"
assert_contains "$(cat "$CUCKOO_HOME/_index.md")" "2026-06-20  pending  call-dentist" "add writes index line"

# add dedups a duplicate slug
s2="$(cuckoo add global 2026-07-01 call-dentist)"; assert_eq "call-dentist-2" "$s2" "add dedups slug"

# add rejects a bad due
err="$(cuckoo add global 2026-6-1 bad 2>&1 >/dev/null)"; assert_contains "$err" "invalid due" "add validates due"

# add accepts a timed due
s3="$(cuckoo add global 2026-06-21T14:30 standup)"; assert_eq "standup" "$s3" "add accepts HH:MM"
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement `ensure_dir`, `valid_due`, `cmd_dir`, `cmd_add`; wire into `main`.**

```bash
ensure_dir() {  # $1 tier → mkdir + (project) .gitignore; prints dir
  local tier="$1" dir; dir="$(tier_dir "$tier")" || return 1
  mkdir -p "$dir"
  if [ "$tier" = project ] && [ ! -f "$dir/.gitignore" ]; then printf '*\n' > "$dir/.gitignore"; fi
  printf '%s' "$dir"
}
valid_due() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2})?$ ]]; }

cmd_dir() { local dir; dir="$(ensure_dir "${1:-}")" || { echo "usage: cuckoo dir <global|project>" >&2; return 2; }; printf '%s\n' "$dir"; }

cmd_add() {  # <tier> <due> <slug>
  local tier="${1:-}" due="${2:-}" slug="${3:-}" dir index final n
  dir="$(ensure_dir "$tier")" || { echo "usage: cuckoo add <global|project> <due> <slug>" >&2; return 2; }
  valid_due "$due" || { echo "invalid due: $due (want YYYY-MM-DD or YYYY-MM-DDTHH:MM)" >&2; return 2; }
  [ -n "$slug" ] || { echo "missing slug" >&2; return 2; }
  index="$dir/_index.md"
  [ -f "$index" ] || printf '# cuckoo index — DUE  STATUS  SLUG (DUE = YYYY-MM-DD or YYYY-MM-DDTHH:MM)\n' > "$index"
  final="$slug"; n=1
  while grep -qE "[[:space:]]${final}\$" "$index" 2>/dev/null; do n=$((n+1)); final="${slug}-${n}"; done
  printf '%s  pending  %s\n' "$due" "$final" >> "$index"
  printf '%s\n' "$final"
}
```

Add to `main`'s `case`: `dir) cmd_dir "$@" ;;` and `add) cmd_add "$@" ;;`.

- [ ] **Step 4: Run → pass. Step 5: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat(cli): dir + add (with slug dedup and due validation)"
```

---

## Task 7: `list`

**Files:** Modify `bin/cuckoo`, `tests/run.sh`.

- [ ] **Step 1: Add failing tests**

```bash
new_sandbox
export CUCKOO_NOW_OVERRIDE="2026-06-20T09:00"
cuckoo add global 2026-06-18 overdue-x   >/dev/null
cuckoo add global 2026-06-20 today-y     >/dev/null
cuckoo add global 2026-06-25 soon-z      >/dev/null
out="$(cuckoo list)"
assert_contains "$out" "overdue-x" "list: shows tasks"
assert_contains "$out" "overdue"   "list: flags overdue"
assert_contains "$out" "today"     "list: flags today"
assert_contains "$out" "upcoming"  "list: flags upcoming"
# sorted: overdue before soon
case "$out" in *overdue-x*soon-z*) : ;; *) assert_eq "sorted" "unsorted" "list: sorted by due";; esac
```

- [ ] **Step 2: Run → fail. Step 3: Implement `cmd_list` + `_list_tier`; wire `list) cmd_list "$@" ;;`.**

```bash
_list_tier() {  # $1 label  $2 index → emits "due label slug" for pending
  [ -f "$2" ] || return 0
  awk -v label="$1" '/^[[:space:]]*#/{next} /^[[:space:]]*$/{next} NF>=3 && $2=="pending"{printf "%s %s %s\n",$1,label,$3}' "$2"
}
cmd_list() {
  local now today; now="$(cuckoo_now)"; today="${now:0:10}"
  { _list_tier global "$(global_dir)/_index.md"; _list_tier project "$(project_dir)/_index.md"; } \
  | sort | awk -v today="$today" '{
      d=substr($1,1,10);
      flag=(d<today)?"overdue":((d==today)?"today":"upcoming");
      printf "  [%s] %-16s %s  (%s)\n", $2, $1, $3, flag
    }'
}
```

- [ ] **Step 4: Run → pass. Step 5: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat(cli): list pending tasks across tiers, sorted with status flags"
```

---

## Task 8: `remove`/`done` + `reschedule`

**Files:** Modify `bin/cuckoo`, `tests/run.sh`.

- [ ] **Step 1: Add failing tests**

```bash
new_sandbox
cuckoo add global 2026-06-20 task-a >/dev/null
cuckoo add global 2026-06-21 task-b >/dev/null
# remove (alias done) drops only the named line
cuckoo remove global task-a
idx="$(cat "$CUCKOO_HOME/_index.md")"
assert_missing  "$idx" "task-a" "remove: drops task-a"
assert_contains "$idx" "task-b" "remove: keeps task-b"
# reschedule updates the due
cuckoo reschedule global task-b 2026-07-15T08:00
assert_contains "$(cat "$CUCKOO_HOME/_index.md")" "2026-07-15T08:00  pending  task-b" "reschedule: updates due"
# done is an alias of remove
cuckoo done global task-b
assert_missing "$(cat "$CUCKOO_HOME/_index.md")" "task-b" "done: alias of remove"
```

- [ ] **Step 2: Run → fail. Step 3: Implement `cmd_remove`, `cmd_reschedule`; wire
  `remove|done) cmd_remove "$@" ;;` and `reschedule) cmd_reschedule "$@" ;;`.**

```bash
cmd_remove() {  # <tier> <slug>
  local dir index tmp; dir="$(tier_dir "${1:-}")" || { echo "usage: cuckoo remove <global|project> <slug>" >&2; return 2; }
  index="$dir/_index.md"; [ -f "$index" ] || return 0
  tmp="$(mktemp)"
  awk -v slug="${2:-}" '/^[[:space:]]*#/{print;next} ($3==slug){next} {print}' "$index" > "$tmp" && mv "$tmp" "$index"
}
cmd_reschedule() {  # <tier> <slug> <new-due>
  local dir index tmp; dir="$(tier_dir "${1:-}")" || { echo "usage: cuckoo reschedule <global|project> <slug> <new-due>" >&2; return 2; }
  valid_due "${3:-}" || { echo "invalid due: ${3:-}" >&2; return 2; }
  index="$dir/_index.md"; [ -f "$index" ] || { echo "no such task" >&2; return 1; }
  tmp="$(mktemp)"
  awk -v slug="${2:-}" -v due="$3" '/^[[:space:]]*#/{print;next} ($3==slug){printf "%s  %s  %s\n",due,$2,$3;next} {print}' "$index" > "$tmp" && mv "$tmp" "$index"
}
```

- [ ] **Step 4: Run → pass. Step 5: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat(cli): remove/done + reschedule"
```

---

## Task 9: Register the SessionStart hook

**Files:** Create `hooks/hooks.json`.

- [ ] **Step 1: Write `hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/bin/cuckoo\" check", "async": false }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify JSON parses.** Run:
  `python3 -c "import json; json.load(open('hooks/hooks.json')); print('ok')"` → `ok`

- [ ] **Step 3: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat(hooks): SessionStart runs cuckoo check"
```

---

## Task 10: The `/cuckoo:schedule` skill

**Files:** Create `skills/schedule/SKILL.md`.

- [ ] **Step 1: Write `skills/schedule/SKILL.md`**

````markdown
---
name: schedule
description: Schedule, list, complete, or reschedule Cuckoo reminders. Use when the user asks to be reminded of something on a future date/time, to schedule a task, or to manage their Cuckoo calendar.
argument-hint: "<add|list|done|reschedule> ..."
---

# Cuckoo — schedule

Manage the user's durable reminders via the `cuckoo` CLI (on `PATH` while this plugin is enabled).
Two tiers: **global** (`~/.claude/cuckoo/`) for personal/cross-project tasks, **project**
(`<project>/.cuckoo/`) for tasks tied to the current repo. Today's date is in the session context
(`currentDate`); the user's timezone is local. Parse the first token of `$ARGUMENTS` as the
subcommand.

## add — `add <when> <what>` [--global | --project]
1. Resolve `<when>` to a token: date only → `YYYY-MM-DD`; with a time → `YYYY-MM-DDTHH:MM` (24h).
   Resolve relative phrases ("tomorrow", "next friday", "in 3 days", "today 14:30") from `currentDate`.
2. Tier: `--global`/`--project` wins; else default **global** (use **project** only when the task is
   clearly about the current repo; `--project` requires being inside a project).
3. Make a short kebab-case slug from `<what>`.
4. Register it — the CLI dedups and prints the final slug:
   `slug="$(cuckoo add <tier> <due> <candidate-slug>)"`
5. Write the body file at `"$(cuckoo dir <tier>)/$slug.md"`:
   ```
   # <human title>
   - due: <due>
   - created: <currentDate>
   - tier: <tier>

   <body — the reminder text, or a full instruction prompt for you to run when it fires>
   ```
6. Confirm: title, resolved due (with time if any), tier. If a time was set, note it surfaces at the
   first session at/after that minute — not a real-time alarm.

## list — `list`
Run `cuckoo list` and present the pending tasks (already sorted, flagged overdue/today/upcoming).

## done — `done <slug>`  (alias: delete)
`cuckoo done <tier> <slug>` then `rm -f "$(cuckoo dir <tier>)/<slug>.md"`. If the user didn't name the
tier, find it via `cuckoo list`. Confirm.

## reschedule — `reschedule <slug> <when>`
Resolve `<when>` as in `add`, then `cuckoo reschedule <tier> <slug> <new-due>`; also update the
`due:` line inside the task's `<slug>.md`. Confirm.

## When a task fires (SessionStart hook output)
At session start the hook lists any due task as `• [tier] <slug> (due …) -> <path>`. Read that file,
surface it to the user, offer to act on its body, then ask whether to mark it **done** or
**reschedule**.
````

- [ ] **Step 2: Acceptance check (manual, recorded in README Task 11).** No automated test — the skill
  is model-executed; correctness of the CLI calls it makes is covered by Tasks 2–8.

- [ ] **Step 3: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "feat(skill): /cuckoo:schedule (add/list/done/reschedule)"
```

---

## Task 11: README + local end-to-end test

**Files:** Rewrite `README.md`.

- [ ] **Step 1: Write the full `README.md`** covering:
  - What it is + the tickler-file concept; the "resurfaces at next session ≥ due" semantics (and the
    honest "not a real-time alarm" note; Google Calendar is the future path to push).
  - Install: `/plugin marketplace add driversti/claude-cuckoo` → `/plugin install cuckoo@cuckoo`.
  - Usage: `/cuckoo:schedule add tomorrow 9am "..."`, `list`, `done`, `reschedule`; global vs project.
  - How it works (hook + `bin/cuckoo` + data dirs); token economy (idle ≈ 0).
  - Dev: `claude --plugin-dir ./claude-cuckoo`, `/reload-plugins`, `bash tests/run.sh`.
  - Privacy (local-only, `.cuckoo/` gitignored), license.

- [ ] **Step 2: Full suite green.** Run: `bash tests/run.sh` → `N run, 0 failed`.

- [ ] **Step 3: Manual end-to-end via `--plugin-dir`** (record result in PR/notes):
  1. `claude --plugin-dir /Users/driversti/Projects/claude-cuckoo`
  2. `/cuckoo:schedule add today "smoke test"` → confirm file + index line created under
     `~/.claude/cuckoo/`.
  3. Start a new session the same way → confirm the hook surfaces `[global] smoke-test`.
  4. `/cuckoo:schedule done smoke-test` → confirm it's gone.
  5. (optional) `claude plugin validate` if available → no errors.

- [ ] **Step 4: Commit**

```bash
git -C /Users/driversti/Projects/claude-cuckoo add -A
git -C /Users/driversti/Projects/claude-cuckoo commit -m "docs: full README + verified local end-to-end"
```

---

## Task 12: Final review (and publish — gated on the user)

- [ ] **Step 1:** Dispatch a final code review over the whole tree (bash quoting, `set -u` safety,
  cross-platform `awk`/`date`/`mktemp`, JSON validity, no hardcoded user paths in shipped files).
- [ ] **Step 2:** Address any high-priority findings; keep the suite green.
- [ ] **Step 3: Publish — ASK THE USER FIRST** (external, public). On approval: create the GitHub repo
  (`gh repo create driversti/claude-cuckoo --public --source . --push`), confirm public/private, then
  share the two install commands. *(Do not push to GitHub without explicit confirmation.)*
- [ ] **Step 4 (post-v1, separate):** Migrate the personal ad-hoc scheduler (`~/.claude/scheduled/` +
  the Balloon Bonanza task + the hand-added global `settings.json` hook) onto Cuckoo, then remove the
  ad-hoc hook to avoid double-surfacing.

---

## Self-review notes
- **Spec coverage:** manifests+marketplace (Task 1), portable hook/CLI (2–9), `/cuckoo:schedule`
  add/list/done/reschedule (10), two tiers (5–8), HH:MM + boundary (4), token economy (hook prints
  only when due — 3/5), distribution + dev workflow (1/11), privacy `.cuckoo` gitignore (6/11),
  testing (2–8). Future items (Google Calendar, in-session timer, recurring, snooze) intentionally
  out of scope.
- **Type/name consistency:** index columns `DUE STATUS SLUG`; CLI verbs `check|list|dir|add|remove|
  reschedule` (+ `done` alias) used identically in the skill and hook; env seams `CUCKOO_NOW_OVERRIDE`
  / `CUCKOO_HOME` / `CLAUDE_PROJECT_DIR` consistent across CLI and tests.
- **No placeholders:** every code step ships complete content (LICENSE is the standard MIT text).
