---
name: plan-execution
description: Execute an approved TODO.md one increment at a time under strict TDD - tests first, code review, atomic commit and push, draft PR opened in the browser, then halt for the author's review. Use when implementing a plan produced by plan-writing, or when resuming work on an existing TODO.md.
---

# Plan Execution

You are the **Developer**. Execute the approved state machine in `TODO.md`
**sequentially** — one increment at a time, never starting the next until the
current one's gate clears.

The plan is not yours to redesign. If an increment turns out to be wrong or
mis-sized, say so and stop; re-planning is `plan-writing`'s job.

## The loop

1. Read `TODO.md` in the repository root and find the first increment that is
   not done. Work only on that one.

2. **Write tests — before touching the code.** A test that passes before the
   implementation tests nothing; if it is green already, the assertion is wrong,
   not the code.

   **This holds for changes as well as additions.** When the work modifies
   existing behaviour, edit that behaviour's *test* to assert the new
   expectation and watch it fail against the current code, then change the
   implementation. Do not change the code first and update the tests to match —
   a test rewritten around code you already wrote only restates what that code
   does, and cannot show the change was the one intended. (For a *bug*, the
   `bug-fixing` skill governs and says the same thing.)

3. **Implement code.** The minimum that makes the failing test pass. Refactor
   here, under green tests — it is part of this step, not a separate one.

   Run only the **relevant** test files while looping; the full suite is the
   commit gate's job.

   **Then loop back to step 2** for the next behaviour in this increment, and
   keep cycling until everything under *Delivers* is built.

4. **Code review.** Run `/code-review high` — or whatever level the plan
   records — and **fix what it finds**. The step ends when the review is clean,
   not when it has been read.

5. **Atomic commit and push.** One commit carrying tests and code **together**,
   then `git push`. Never split tests and implementation across commits: one
   commit keeps every point in history independently verifiable and makes a
   revert a single operation.

   The pre-commit hook is the enforcement point. If it fails, **fixing it is
   part of this step** — `--no-verify` is cheating and is never allowed. The
   step is done only once the push succeeds.

6. **Draft PR.** `gh pr create --draft --reviewer <the user>` on the branch's
   first push, or confirm the existing draft picked up the push. Then
   `gh pr view --web` to open it in the browser — **every increment, not just
   the first**. Watch for review comments and address them as they land. The
   step ends when the PR is marked ready for review, or the user says it is done.

7. 🛑 **MANUAL GATE.** The work is **blocked** on the author's review in the
   browser. Do not start the next increment until this PR is approved, marked
   ready for review, or the user explicitly says to move on. A gate, not a
   formality — no "proceeding while you look".

## Keeping TODO.md current

Tick each checkbox the moment it completes, and keep the progress table at the
top of the file in step — that table is how the user knows where things stand,
and a stale row is worse than no table. Record each increment's PR link there
as it is opened.
