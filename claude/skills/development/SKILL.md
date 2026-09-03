---
name: development
description: How development work is done here - every task runs writing tests, coding, bot review, draft pr, author review, in that order, tests always first and never --no-verify. Use whenever you are about to write or change code - building a feature, fixing a bug, refactoring, adjusting behaviour - whether or not a plan or TODO.md exists.
---

# Development

This strictly governs all work, whether a plan/`TODO.md` exists or not.

## What a task is
A **task** is a self-contained, mergeable PR. 
* **TDD Loop:** TDD runs *inside* a task (failing test ➔ code). The entire cycle lands in **one atomic commit**.
* **Execution:** Strictly sequential. One task/branch at a time. Next task blocked until current `author review` clears.
* **Branching:** Implicit upon starting.
* **Size Limits:** Max ~15 files or a few hundred lines. Split PRs and tests along seams if exceeded.

## The Five Steps (Execute sequentially)

### 1. writing tests
**Always first.** Assert new expectations/changes and watch tests fail *before* touching implementation.

### 2. coding
Implement minimum code to pass. **Refactor here** under green tests. Loop back to Step 1 until complete.

### 3. bot review
Run `/code-review high` (or planned level). **Fix all findings.** Step ends only when clean.

### 4. draft pr
Commit, push, and open the draft PR.
* **One atomic commit:** Tests and code together.
* **`--no-verify` is never allowed:** Fix pre-commit hook failures natively. 
* Execute `gh pr create --draft --reviewer <the user>` on first push. Execute `gh pr view --web` for every task.

### 5. author review
🛑 **HARD STOP.** Work is blocked on GitHub PR review.
* **Poll GitHub (Do not wait in chat):** 
  ```bash
  gh pr view --json reviews,comments --jq '{reviews: .reviews, comments: .comments}'
  gh api "repos/{owner}/{repo}/pulls/$(gh pr view --json number --jq .number)/comments"
  gh api "repos/{owner}/{repo}/issues/comments/<comment-id>/reactions"
  gh api "repos/{owner}/{repo}/pulls/comments/<comment-id>/reactions"
  ```
* **Communicate on GitHub:** Reply directly on the PR via `gh pr comment` or `gh api .../replies`.
* **Sign Comments:** `gh` authenticates as the user, so prefix every comment,
  unless using a dedicated bot token:

  ```markdown
  > 🤖 **Claude** · posted via `gh` as @<the user>
  ```

  Track comment IDs to avoid self-replying.
* **Action Loop:**
  * **👍 Reaction:** Approval. Proceed.
  * **Written Reply:** Act on it, fix, push to same branch, and reply on thread. Do not batch silently.
  * **Silence:** Keep polling.
* **Escalation:** Escalate to chat *only* if genuinely blocked by missing authorization or ambiguous paths.
* **Completion:** Step ends when PR is marked ready for review.

## Workflow Rules
* **Five is a baseline:** Add short, lowercase steps (e.g., `migration`) only if justified. Must be pre-approved in the plan.
* **Proportionality:** Genuine one-line fixes (typos, version bumps) skip this ceremony. All behavioural changes require all five steps.
* **When `TODO.md` exists:**
  * Work only the first undone task.
  * Tick checkboxes immediately (status is strictly derived from ticks).
  * Sync with `PLAN.html` for scope/architecture.
  * If mis-sized, halt for re-planning by `plan-writing`.
