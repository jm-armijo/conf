---
name: bug-fixing
description: Rules for triaging and fixing reported bugs. Use when acting on a bug report, a code-review finding, or any claim that code is defective.
---

# Bug Fixing

## 1. Reproduce with a failing test before fixing

Whenever a bug becomes known — you catch it, the user reports it, a review finds it, a
stack trace shows it — the order is **fixed and non-negotiable**:

1. Write a regression test that reproduces the issue.
2. **Run it and watch it fail**, for the actual reason the bug exists. A test that passes
   before the fix reproduces nothing; a test that fails on a typo or a missing import is
   not a reproduction either. Confirm the failure mode matches the reported one.
3. Only then write the fix.
4. Re-run: the same test must now pass, and the rest of the suite must stay green.

Do not write the fix first and add a test afterwards. Do not fix and test in one pass. A
test written after a fix only proves the code does what it now does — it cannot show the
bug was ever present, so it is worth far less as a guard against regression.

### When reproducing is not possible

If you cannot write a reproducing test, **stop and tell the user why** before fixing
anything. Name the specific obstacle — no seam to inject at, the failure needs a live
network or GPU, it depends on a race, the harness cannot reach that code path. Propose the
closest alternative you can (a narrower unit test, a manual verification, a temporary
assertion) and let the user decide. Do not silently skip the test and proceed.

### Overriding

Only a **direct instruction from the user** overrides this rule — "just fix it", "skip the
test", or similar. Time pressure, a one-line change, an "obvious" fix, or your own
confidence are not overrides. When the user does override, say so plainly in your summary,
so the missing coverage is visible rather than assumed.

## 2. Record refuted findings in the code

A refuted finding is one that was **investigated and confirmed not to be a bug**. Never
apply this rule to a finding that was merely deprioritized, or that you did not verify.

Once a finding is refuted, the required action depends on **who raised it**:

- **Raised by a Claude code review** (`/code-review`, an automated reviewer agent, or any
  other non-human source): add a code comment at the relevant code explaining **why it is
  not a bug**. Do not ask first.
- **Raised by a human** (the user, a teammate, a PR comment): **ask the user** whether to
  add the comment. Do not add it unprompted.

### Why

The comment exists to stop the next reviewer — human or automated — from re-raising a
question that has already been settled, and from "fixing" correct code on a second pass.
The human case is gated on asking because a human reviewer can be told the answer
directly, and the code may not be where that explanation belongs.

### Writing the comment

- State the **mechanical reason** the behavior is correct, not that a review asked about it.
  The comment must be useful to someone who never saw the review.
- Place it at the code the finding pointed to — the line, branch, or guard itself.
- Keep it to the reason. No finding IDs, no reviewer names, no dates.

```python
# Tested per row rather than across the batch: an all-or-nothing check would
# either keep a duplicate on every row or strip a real token from rows that
# never carried the prefix.
```

Not this:

```python
# Code review flagged this as a bug (F3) but it is fine.
```
