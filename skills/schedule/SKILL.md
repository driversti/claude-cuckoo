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
