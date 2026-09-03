---
name: development
description: How development work is done here - every task runs writing tests, coding, bot review, draft pr, author review, in that order, tests always first and never --no-verify. Use whenever you are about to write or change code - building a feature, fixing a bug, refactoring, adjusting behaviour - whether or not a plan or TODO.md exists.
---

# Development

This is how work gets done here — not a mode to enter after a plan is approved.
The steps below apply to **every piece of work**, whether or not a plan or
`TODO.md` exists.

## What a task is

A **task** is a self-contained slice of work worth a pull request on its own — a
reviewer can read it, judge it, and merge it by itself. Not one function and its
tests; that is too small to open a PR for.

- TDD runs *inside* a task: failing test, code, next failing test, code. The
  whole cycle lands in **one commit**. A general case and its edge case are the
  same task.
- Tasks run **strictly sequentially** — one at a time, one branch each, no
  parallel branches. The next does not begin until the current one's `author
  review` clears.
- **Branch creation is implicit**, not a step: cut the branch as work begins.
  Where a plan exists, it names the branch.

### A task is too big when the PR is too big

**A PR touching more than ~15 files, or more than a few hundred changed lines,
is too big** — split it. This ceiling beats the "worth a PR on its own" floor
whenever the two pull against each other. Judge size **before** work starts; if a
task heads past the bound mid-flight, stop and re-split.

Entangled tests are **not** a reason to merge tasks. Split the test file along
the same seam as the code and land each piece with the change it covers — that
is what keeps every commit independently green.

## The five steps

Every task runs all five, in order. Use these names verbatim, in `TODO.md` and
when saying where you are.

### 1. writing tests

**Before touching the code.** A test that is green before the implementation
exists has a wrong assertion.

**This holds for *changes* as well as additions.** When modifying existing
behaviour, edit that behaviour's test to assert the new expectation and watch it
fail, then change the implementation. Never edit the code first and adjust the
tests after. (For a *bug*, the `bug-fixing` skill governs and says the same.)

### 2. coding

The minimum that makes the failing test pass. **Refactor here**, under green
tests — part of this step, not a separate one. Run only the **relevant** test
files while looping; the full suite is the commit hook's job. **Then loop back to
step 1** for the next behaviour, until the task's slice is built.

### 3. bot review

Run `/code-review high` — or whatever level the plan records, or the user set —
and **fix what it finds**. The step ends when the review is clean, not when it
has been read.

### 4. draft pr

Commit, push, and open the draft PR. One step, because a GitHub draft PR cannot
exist without a commit and a push behind it.

- **One atomic commit** carrying tests and code **together**. Never split them
  across commits.
- **`--no-verify` is never allowed.** When the pre-commit hook fails, **fixing
  it is part of this step**. The step is not done until the hook passes on its
  own merits and `git push` succeeds.
- `gh pr create --draft --reviewer <the user>` on the branch's first push, or
  confirm the existing draft picked up the push. Then `gh pr view --web` —
  **every task, not just the first**.

### 5. author review

🛑 **HARD STOP.** The work is **blocked** on the author's review of the draft PR.

**Poll the PR for comments; do not wait to be told** — feedback arrives on
GitHub, not in the chat. Check regularly for the whole duration of this step:

```bash
gh pr view --json reviews,comments --jq '{reviews: .reviews, comments: .comments}'
gh api "repos/{owner}/{repo}/pulls/$(gh pr view --json number --jq .number)/comments"
```

The second call is the one that matters: `gh pr view` misses **inline review
comments left on specific lines**, where most substantive feedback lands. Poll
both.

**The PR is where the conversation happens, not the chat.** Reply **on GitHub**,
so the feedback, reasoning and decision stay in the tracked artifact.

The loop is:

1. The author comments.
2. You reply on the PR — what you will change, or why you think otherwise.
3. You keep polling.
4. The author signals:
   - **👍 reaction** — approval of your reply's approach. Proceed; no further
     reply needed.
   - **A written reply** — act on it, and keep iterating on the thread until it
     settles.
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
attributes your comments to *them*. Open every comment you write with:

```markdown
> 🤖 **Claude** · posted via `gh` as @<the user>
```

It is the only thing distinguishing your voice from the author's, and must not be
removed as noise. If the repo has a GitHub App or bot account with its own token,
use that instead and drop the marker — but do not create such an identity
yourself.

Track the comment IDs you post and skip them when polling, or you will answer
yourself.

Address each comment as it lands — fix it, push to the same branch, and reply on
the thread saying what changed. Do not batch fixes silently, and do not mark
anything resolved you have not fixed. Questions get answered; disagreement gets a
reasoned reply, not silent compliance or silent refusal.

**Escalate to the chat only when the work is genuinely blocked** — an
authorization you cannot infer, or a decision where either path risks wasted
work. Everything else goes on the PR.

The step ends when the PR is marked ready for review, or the user explicitly says
to move on. A gate, not a formality — no "proceeding while you look", and no
starting the next task.

## Five is the baseline, not a ceiling

**Add a step when the task genuinely needs one** — a data migration, a manual
verification no test covers, a deploy to stage. Give it a short lowercase name
(`migration`, `manual check`) and put it in sequence. Any added step must be
**shown in the plan** so the user can veto it before work starts; do not invent
one mid-task.

## Proportionality

A genuine one-line fix — a typo, a version bump — does not need PR-sized
ceremony. Anything that changes behaviour gets all five steps, and if you are
arguing with yourself about whether it counts, it counts.

## When a TODO.md exists

Read it. Work the first task that is not done, and only that one.

- **Track where you are** — which task, which step — and tick each checkbox the
  moment it completes. Status is derived from the checkboxes and nothing else,
  so an unticked box means the step did not happen.
- **Refer to `PLAN.html`** for architecture, scope, and the reasoning behind the
  split. Task numbering and names must stay in sync with it; change one, change
  both.
- The plan is not yours to redesign. If a task is wrong or mis-sized, say so and
  stop — re-planning is `plan-writing`'s job.
