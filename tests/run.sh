#!/usr/bin/env bash
# tests/run.sh — run with: bash tests/run.sh
. "$(dirname "$0")/lib.sh"

# ── Task 2: check: nothing scheduled → silent ────────────────────────────────
new_sandbox
out="$(cuckoo check)"
assert_empty "$out" "check: empty sandbox is silent"

# ── Task 3: check — global tier, date-only due ───────────────────────────────

# check: past-due date-only global task surfaces
new_sandbox
export CUCKOO_NOW_OVERRIDE="2026-06-20T09:00"
printf '2026-06-20  pending  call-dentist\n' > "$CUCKOO_HOME/_index.md"
out="$(cuckoo check)"
assert_contains "$out" "[global] call-dentist (due 2026-06-20)" "check: surfaces due global task"
assert_contains "$out" "announce each due reminder" "check: prints surfacing instruction"

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

# ── Task 4: check — timed (HH:MM) due, with boundary ────────────────────────

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

# ── Task 5: check — project tier + robustness ────────────────────────────────

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

# ── Task 6: dir + add (with slug dedup) ──────────────────────────────────────

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

# ── Task 7: list ─────────────────────────────────────────────────────────────

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

# ── Task 8: remove/done + reschedule ─────────────────────────────────────────

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

# ── Review hardening (code-quality findings) ─────────────────────────────────

# add: exact-match dedup — a slug with a regex metachar is NOT falsely deduped
new_sandbox
cuckoo add global 2026-06-20 my-task >/dev/null
s="$(cuckoo add global 2026-06-21 my.task)"
assert_eq "my.task" "$s" "add: dotted slug not falsely deduped against my-task"

# remove: missing slug errors (no silent no-op)
new_sandbox
err="$(cuckoo remove global 2>&1 >/dev/null)"
assert_contains "$err" "missing slug" "remove: errors on missing slug"

# reschedule: non-existent slug errors with non-zero exit
new_sandbox
cuckoo add global 2026-06-20 exists-x >/dev/null
if cuckoo reschedule global ghost 2026-07-01 2>/dev/null; then rc=0; else rc=1; fi
assert_eq "1" "$rc" "reschedule: errors on non-existent slug"

# reschedule: missing slug errors
new_sandbox
err="$(cuckoo reschedule global 2>&1 >/dev/null)"
assert_contains "$err" "missing slug" "reschedule: errors on missing slug"

finish
