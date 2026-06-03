# Cuckoo 🐦

🇬🇧 English · [🇺🇦 Українська](README.uk.md)

**A durable personal calendar for Claude Code.** Set a reminder for a future date (optionally a
time), and Cuckoo brings it back the next time you start a Claude Code session on or after that date
— like a cuckoo clock popping out at the right moment. It's a *tickler file* for Claude Code.

Reminders live in plain files, so they survive restarts. When nothing is due, Cuckoo costs you
essentially **zero context tokens**.

## How it works

- A **SessionStart hook** runs a tiny command (`cuckoo check`) at the start of every session. It
  reads a small index and prints any due reminders — or stays completely silent.
- A **`/cuckoo:schedule`** command lets you add, list, complete, and reschedule reminders.
- Reminders are stored in two tiers:
  - 🌍 **Global** — `~/.claude/cuckoo/` — personal, works in any project.
  - 📂 **Project** — `<your-repo>/.cuckoo/` — tied to a specific repo (git-ignored by default).

> **Session-triggered, not an alarm clock.** Cuckoo can't push to your phone, and it is not a terminal
> popup. At session start the hook hands any due reminders to Claude, which announces them in its
> **first reply once you send a message** — so a brand-new session you just stare at (without typing
> anything) shows nothing until you say something. A time of day is the *earliest* surfacing moment,
> not a real-time alert. (Calendar/push integration is on the roadmap.)

## Install

```
/plugin marketplace add driversti/claude-cuckoo
/plugin install cuckoo@cuckoo
```

Then restart Claude Code (or run `/reload-plugins`).

## Usage

```
/cuckoo:schedule add tomorrow "email the tax form"
/cuckoo:schedule add 2026-07-01 09:00 "quarterly review"
/cuckoo:schedule add next friday "call the dentist" --global
/cuckoo:schedule list
/cuckoo:schedule done call-the-dentist
/cuckoo:schedule reschedule quarterly-review "next monday 8am"
```

- Dates resolve in your local timezone; natural language ("tomorrow", "next friday 9am", "in 3
  days") works.
- Default tier is **global**; pass `--project` to scope a reminder to the current repo.

When a reminder is due, your next session opens with a note like:

```
⏰ CUCKOO — scheduled task(s) due
  • [global] call-the-dentist (due 2026-06-20) -> ~/.claude/cuckoo/call-the-dentist.md
```

Claude reads the task, brings it up, offers to act on it, then asks whether to mark it done or
reschedule.

## Why near-zero token cost

The SessionStart hook runs in your shell, not in the model. It reads only a tiny index
(`date · status · slug`) and prints nothing unless something is due. The full text of a reminder
lives in its own file and is read only on the day it fires. An idle session pays only for the
one-line command description.

## Data & privacy

- Everything is local files. No network, no telemetry.
- Project reminders live in `<repo>/.cuckoo/`, which ships with a `.gitignore` (`*`) so your personal
  reminders are never committed.

## Development

```bash
# Load the plugin locally without installing:
claude --plugin-dir /path/to/claude-cuckoo
# After edits:
/reload-plugins
# Run the test suite (zero dependencies):
bash tests/run.sh
```

The data layout and CLI:

```
~/.claude/cuckoo/            # global tier
├── _index.md                #   DUE  STATUS  SLUG   (tiny; the hook reads only this)
└── <slug>.md                #   the reminder body (read only when due)
<repo>/.cuckoo/              # project tier (same layout, + .gitignore '*')

bin/cuckoo  check | list | dir | add | remove | done | reschedule
```

## Roadmap

- **Google Calendar** two-way sync — real device push notifications.
- **In-session precision timer** — fire at the exact minute while a session is open.
- **Recurring** reminders, **snooze**.

## License

MIT © 2026 Yurii Chekhotskyi
