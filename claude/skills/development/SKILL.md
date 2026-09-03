---
name: development
description: How development work is done here - every task runs writing tests, coding, bot review, draft pr, author review, in that order, tests always first and never --no-verify. Use whenever you are about to write or change code - building a feature, fixing a bug, refactoring, adjusting behaviour - whether or not a plan or TODO.md exists.
---

# Development

Applies sequentially to **every piece of work**, regardless of existing plans or `TODO.md` files.

## What a task is

A **task** is a self-contained, mergeable unit of work (one PR).
* **TDD Loop:** TDD runs *inside* a task (failing test ➔ code ➔ next failing test ➔ code). The entire cycle lands in **one atomic commit**.
* **Execution:** Strictly sequential. One task/branch at a time. The next task cannot begin until the current `author review` clears.
* **Branching:** Implicit. Cut the branch when work begins (named by the plan, if applicable).
* **Size Limits:** A PR exceeding ~15 files or a few hundred lines is too big. Split it before starting or mid-flight. Split tests along the same seams to keep commits independently green.

## The Five Steps

Execute all five steps sequentially. Use exact step names in `TODO.md` and status updates.

### 1. writing tests
**Always first.** Write or modify tests to assert new expectations and watch them fail *before* touching implementation. Never code first.

### 2. coding
Implement the minimum code to pass the failing test. **Refactor here** while tests are green. Run only relevant test files. Loop back to Step 1 until the task's slice is built.

### 3. bot review
Run `/code-review high` (or planned level). **Fix all findings.** Step ends only when the review is clean.

### 4. draft pr
Commit, push, and open the draft PR as a single action.
* **One atomic commit** containing tests and code together.
* **`--no-verify` is never allowed.** Fixing pre-commit hook failures is part of this step.
* Execute `gh pr create --draft --reviewer <the user>` on the first push. Execute `gh pr view --web` for *every task*.

### 5. author review
🛑 **HARD STOP. Blocked on the author's GitHub review.**

* **Poll for feedback:** Do not wait in chat. Continuously poll GitHub for PR-level comments, inline comments, and reactions:
  ```bash
  gh pr view --json reviews,comments --jq '{reviews: .reviews, comments: .comments}'
  gh api "repos/{owner}/{repo}/pulls/$(gh pr view --json number --jq .number)/comments"
  gh api "repos/{owner}/{repo}/issues/comments/<comment-id>/reactions"
  gh api "repos/{owner}/{repo}/pulls/comments/<comment-id>/reactions"
  ```
  `gh pr view` misses inline comments, and reactions are on a third endpoint. Poll all of them.
* **Converse on the PR, not in chat.** The decision record belongs with the artifact.
* **Signals:** 👍 on your reply = approved, proceed. A written reply = act on it, keep iterating. Silence = keep polling.
* **Sign every comment.** `gh` authenticates as the user, so GitHub attributes your comments to them. Open each one with `> 🤖 **Claude** · posted via ` `gh` ` as @<the user>`. Track the IDs you post and skip them when polling, or you will answer yourself.
* **Escalate to chat only when genuinely blocked** — an authorization you cannot infer. Disagreement goes on the PR.
* Step ends when the PR is marked ready for review, or the user says to move on.

## Adding steps

Five is the baseline. Add a step a task genuinely needs (`migration`, `manual check`) in the same lowercase style, and show it in the plan so it can be vetoed. Never invent one mid-task.

## Proportionality

A one-line fix (typo, version bump) does not need the full ceremony. Anything that changes behaviour gets all five steps; if you are arguing about whether it counts, it counts.

## When a TODO.md exists

Read it. Work the first undone task, and only that one.
* Tick each checkbox as it completes — status is derived from the boxes, so an unticked box means the step did not happen.
* Refer to `PLAN.html` for scope and reasoning. Keep task numbering in sync with it.
* The plan is not yours to redesign. If a task is wrong or mis-sized, stop and say so — re-planning is `plan-writing`'s job.
