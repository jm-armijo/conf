---
name: development
description: How development work is done here - every task runs writing tests, coding, bot review, draft pr, author review, in that order, tests always first and never --no-verify. Use whenever you are about to write or change code - building a feature, fixing a bug, refactoring, adjusting behaviour - whether or not a plan or TODO.md exists.
---

# Development

This is how work gets done here. **Not a mode, not a phase.** There is no
"execution mode" to enter after a plan is approved, because nobody labels the
moment work starts — you just start. So these steps apply to **every piece of
work**, whether it came from a plan, a one-line request, or a bug report.

## What a task is

A **task** is a self-contained slice of work worth a pull request on its own.
Not one function and its tests — too small to open a PR for. A reviewer should
be able to read it, judge it, and merge it by itself.

TDD runs *inside* a task, as a loop: failing test, code, next failing test,
code, until the task's work is done. The whole cycle lands in **one commit**.
Splitting a general case from its edge case across two tasks is wrong — they
are the same task.

Tasks run **strictly sequentially**. One at a time, one branch each, no
parallel branches, and the next does not begin until the current one's author
review clears.

**Branch creation is implicit**, not a step: cut the task's branch as work on it
begins. Where a plan exists, it names the branch.

## A task is too big when the PR is too big

The upper bound is what a human can actually review in one sitting. **A PR
touching more than ~15 files, or more than a few hundred changed lines, is too
big** — split it. This bound binds harder than the "worth a PR on its own"
floor above: when the two pull against each other, the ceiling wins and the
work splits.

Size is judged **before** work starts, while planning the split, not discovered
at `draft pr` when the diff is already written. If a task turns out mid-flight
to be heading past the bound, stop and re-split rather than pushing through.

Entangled tests are **not** a reason to merge tasks into one. The failure mode
this rule exists to catch: three separate concerns land in one commit because
one test file happened to carry assertions for all three, producing a 33-file
PR that no reviewer can hold in their head. Split the test file along the same
seam as the code, and land each piece with the change it covers. Every commit
must be independently green, but that is satisfied by splitting the tests too —
not by giving up and shipping one large commit.

## The five steps

Every task runs all five, in order. These are the step names — use them
verbatim, in `TODO.md` and when saying where you are.

### 1. writing tests

**Before touching the code.** A test that passes before the implementation
tests nothing; if it is green already, the assertion is wrong, not the code.

**This holds for *changes* as well as additions**, and that is where the habit
breaks. When the work modifies existing behaviour, edit that behaviour's *test*
to assert the new expectation and watch it fail against the current code, then
change the implementation. Never edit the code first and adjust the tests after
— a test rewritten around code you already wrote only restates what that code
does, and cannot show the change was the one intended. (For a *bug*, the
`bug-fixing` skill governs and says the same thing.)

### 2. coding

The minimum that makes the failing test pass. **Refactor here**, under green
tests — it is part of this step, not a separate one.

Run only the **relevant** test files while looping; the full suite is the
commit hook's job.

**Then loop back to step 1** for the next behaviour in this task, and keep
cycling until the task's slice is built.

### 3. bot review

Run `/code-review high` — or whatever level the plan records, or the user set —
and **fix what it finds**. The step ends when the review is clean, not when it
has been read.

### 4. draft pr

Commit, push, and open the draft PR. These are one step because a GitHub draft
PR cannot exist without a commit and a push behind it.

- **One atomic commit** carrying tests and code **together**. Never split them
  across commits: one commit keeps every point in history independently
  verifiable and makes a revert a single operation.
- **`--no-verify` is never allowed.** The pre-commit hook is the enforcement
  point, and when it fails, **fixing it is part of this step** — not skipping
  it, not deferring it. The commit is not done until the hook passes on its own
  merits and `git push` succeeds.
- `gh pr create --draft --reviewer <the user>` on the branch's first push, or
  confirm the existing draft picked up the push. Then `gh pr view --web` to
  open it in the browser — **every task, not just the first**.

### 5. author review

🛑 **HARD STOP.** The work is **blocked** on the author's review of the draft PR
in the browser.

**Poll the PR for comments; do not wait to be told.** Review feedback arrives on
GitHub, not in the chat, so nothing surfaces it unless you go and look. Check
regularly for the whole duration of this step:

```bash
gh pr view --json reviews,comments --jq '{reviews: .reviews, comments: .comments}'
gh api "repos/{owner}/{repo}/pulls/$(gh pr view --json number --jq .number)/comments"
```

The second call is the one that matters: `gh pr view` misses **inline
review comments left on specific lines**, which is where most substantive
feedback lands. Poll both.

**The PR is where the conversation happens, not the chat.** Review is an
engineering conversation and it belongs in the tracked artifact: someone reading
the PR a year from now should see the feedback, the reasoning, and the decision
without needing a terminal transcript that no longer exists. So reply **on
GitHub**, not in the chat.

The loop is:

1. The author comments.
2. You reply on the PR — what you will change, or why you think otherwise.
3. You keep polling.
4. The author signals:
   - **👍 reaction** — approval of the approach in your reply. Proceed with it.
     No further reply needed; just do it.
   - **A written reply** — read it and act on what it says. It may be a
     direction to follow, or the next turn of an ongoing discussion. Keep
     iterating on the thread until it settles.
   - **Nothing yet** — keep polling. Silence is not consent.

Reactions live on a **different endpoint from comments** and are invisible to
`gh pr view`, so poll them explicitly or you will miss every 👍:

```bash
# issue-level comments
gh api "repos/{owner}/{repo}/issues/comments/<comment-id>/reactions"
# inline review comments
gh api "repos/{owner}/{repo}/pulls/comments/<comment-id>/reactions"
```

Reply mechanics: `gh pr comment <n> --body-file <file>` for a PR-level comment,
and `gh api "repos/{owner}/{repo}/pulls/<n>/comments/<comment-id>/replies" -f
body=...` to reply inside an inline thread rather than starting a new one.

**Sign every comment you post.** `gh` authenticates as the user, so GitHub
attributes your comments to *them* — without a marker the thread reads as the
author talking to themselves, and the review record loses who actually said
what. Open every comment you write with:

```markdown
> 🤖 **Claude** · posted via `gh` as @<the user>
```

This is not decoration and must not be removed as noise: it is the only thing
distinguishing your voice from the author's in a thread where the API reports
one identity for both. It survives quoting, and it is greppable when auditing
the history later.

If the repo has a GitHub App or a bot account with its own token, use that
instead and drop the marker — real attribution beats a convention. Do not
create such an identity yourself; that is the user's to provision.

Track the comment IDs you post. When polling, skip them — otherwise you will
read your own replies back as new feedback and answer yourself.

Address each comment as it lands — fix it, push to the same branch, and reply on
the thread saying what changed. Do not batch a pile of fixes silently, and do not
mark anything resolved that you have not actually fixed. Comments that are
questions get answered; comments you disagree with get a reasoned reply rather
than silent compliance or silent refusal.

**Escalate to the chat only when the work is genuinely blocked** — an
authorization you cannot infer, or a decision where proceeding either way risks
wasted work. Everything else, including disagreement, goes on the PR.

Keep polling until the step ends: the PR is marked ready for review, or the user
explicitly says to move on.

The step ends when the PR is marked ready for review, or the user explicitly
says to move on. A gate, not a formality — no "proceeding while you look", and
no starting the next task.

## Five is the baseline, not a ceiling

**Add a step when the task genuinely needs one** — a data migration to run, a
manual verification no test covers, a deploy to stage. Give it a short name in
the same lowercase style (`migration`, `manual check`) and put it in sequence.

Any added step must be **shown in the plan** so the user can veto it before the
work starts. Do not invent one mid-task.

## Proportionality

A genuine one-line fix — a typo, a version bump — does not need a PR-sized
ceremony. Scale the ritual to the work. This is not an escape hatch: anything
that changes behaviour gets all five steps, and if you are arguing with
yourself about whether it counts, it counts.

## When a TODO.md exists

Read it. Work the first task that is not done, and only that one.

- **Track where you are** — which task, which step — and tick each checkbox the
  moment it completes. Status in `TODO.md` is derived from the checkboxes and
  nothing else, so an unticked box means the step did not happen.
- **Refer to `PLAN.html`** for architecture, scope, and the reasoning behind the
  split. Task numbering and names must stay in sync with it; if you change one,
  change both.
- The plan is not yours to redesign. If a task turns out to be wrong or
  mis-sized, say so and stop — re-planning is `plan-writing`'s job.
