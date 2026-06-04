---
name: goal
description: Advance the whoop-local project by one increment toward GOAL.md. Reads CLAUDE.md + GOAL.md, picks the next unchecked task, implements and tests it locally, ticks it off, logs progress, and commits. Optional arg targets a phase/task, e.g. "/goal phase 2".
---

# /goal — advance the project autonomously

You are working toward the roadmap in `GOAL.md`, under the rules in `CLAUDE.md`. Each run moves the project forward by one well-tested increment. Optional `$ARGUMENTS` names a phase or task to target; otherwise take the next unchecked item top-to-bottom.

## Loop
1. **Orient.** Read `CLAUDE.md` (constraints, conventions, run/test commands, human-in-the-loop rules) and `GOAL.md` (phases + Progress log). If `$ARGUMENTS` is set, focus there; else select the topmost unchecked task.
2. **Plan.** State, in 2–4 lines, the task and how you'll satisfy its acceptance criteria. Don't ask permission for ordinary coding work — just proceed.
3. **Implement.** Write/edit code to the conventions in CLAUDE.md. Keep decode logic pure and unit-testable on captured bytes.
4. **Verify.**
   - Add/extend tests. Run `pytest -q` and `ruff check .`.
   - If the task needs the **physical band** (live values, real packet capture, decode validation, buffer-depth measurement): **stop and hand it to the user** with exact, numbered steps for what to capture or confirm, and what to paste back. **Never fabricate sensor values to make a test pass.**
5. **Record.** When acceptance criteria are met: tick the checkbox in `GOAL.md` and prepend a dated entry to its Progress log (what changed, any caveats, any follow-up).
6. **Commit.** One focused commit with a clear message (e.g. `feat(collector): decode HR + RR with CRC check`). **Do not push.**
7. **Continue or stop.** Repeat for the next task until: the phase completes, a task needs the band/human, or you hit a real blocker. Then stop and summarise what you did, what's next, and anything you need from the user.

## Guardrails (hard)
- Local-only; never add cloud calls, telemetry, or public network exposure. Never require the WHOOP app/cloud.
- Never delete the database or captured data. Never push, deploy, or run destructive shell commands without explicit user confirmation.
- Never copy code from unlicensed/incompatible repos (see CLAUDE.md). Add attribution when porting from permissively-licensed references.
- Don't present any computed metric as "WHOOP's" — label derived values as our own estimates.
- If genuinely blocked or ambiguous about scope, write the blocker into `GOAL.md` (Progress log) and stop cleanly rather than guessing.
