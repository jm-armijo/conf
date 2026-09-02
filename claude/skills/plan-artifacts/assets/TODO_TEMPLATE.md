<!-- Baseline for TODO.md — the execution state machine.

     An increment is a self-contained slice of work worth a pull request on its
     own. Not one function, not one test: a coherent piece a reviewer can read,
     judge, and merge by itself. Sizing it is a judgement call, made at planning
     time and explained in PLAN.html — err toward too large before too small,
     because a PR that isn't worth opening is the wrong unit.

     TDD runs *inside* an increment as a loop: write a failing test, make it
     pass, write the next failing test, make it pass, until the increment's work
     is done. One commit carries the whole cycle.

     Increments are strictly sequential. Do not start the next one until the
     current PR is approved, marked ready for review, or the user says to move on.

     Emit every increment in full: all six steps, every time. No "same as above".
     Delete this comment and every {{PLACEHOLDER}} before writing the file. -->

# {{PLAN_NAME}}

**Outcome:** {{ONE_LINE_OUTCOME}}
**Plan:** `PLAN.html` — architecture, data flow, boundaries crossed.
**Increments:** {{N}} total, one PR each, executed in order.
**Review level:** `/code-review high` <!-- unless the user set another level while planning -->

## Progress

<!-- Every increment, one row. Status: `todo` / `in progress` / `in review` / `done`.
     Update the row the moment the increment's state changes — this table is what the
     user reads first, and a stale row is worse than no table. -->

| # | Increment | Delivers | PR | Status |
|---|-----------|----------|----|--------|
| 1 | {{SHORT_NAME}} | {{WHAT_SHIPS}} | — | todo |
| 2 | {{SHORT_NAME}} | {{WHAT_SHIPS}} | — | todo |
| … | … | … | — | todo |
| {{N}} | {{SHORT_NAME}} | {{WHAT_SHIPS}} | — | todo |

---

## Increment 1 of {{N}} — {{SHORT_NAME}}

**Delivers:** {{THE_SELF_CONTAINED_SLICE_IN_ONE_LINE}}
**Branch:** `{{branch-name}}`

- [ ] **1. Write tests.** Add `{{test/path:test name}}` asserting {{THE_OBSERVABLE_BEHAVIOUR}}.
      Run `{{RELEVANT_TEST_COMMAND}}` — it **must fail** with {{THE_EXPECTED_FAILURE_MESSAGE}}.
      A test that passes before the implementation tests nothing; if it is green
      already, the assertion is wrong, not the code.
- [ ] **2. Implement code.** {{THE_EDIT_IN_ONE_SENTENCE}} in `{{path}}`.
      Run `{{RELEVANT_TEST_COMMAND}}` — passes. Refactor here, under green tests;
      it is part of this step, not a separate one.
      **Then loop back to step 1** for the next behaviour in this increment, and
      keep cycling until everything under *Delivers* is built. Run only the
      relevant test files while looping — the full suite is the commit gate's job.
- [ ] **3. Code review.** Run `/code-review high` and **fix what it finds**.
      This step ends when the review is clean, not when it has been read.
- [ ] **4. Atomic commit (Tests + Code) and push.** One commit carrying both:
      `git commit -m "{{IMPERATIVE_SUBJECT_LINE}}"` then `git push`.
      The pre-commit hook runs the full suite and the lint gates — that is the
      enforcement point. If it fails, **fixing it is part of this step**.
      `--no-verify` is cheating and is never allowed. Done only once push succeeds.
- [ ] **5. Raise the draft PR.** `gh pr create --draft --reviewer {{GITHUB_USER}}`
      (first push on this branch) or confirm the existing draft picked up the push.
      Then `gh pr view --web` to open it in the browser — **every increment, not
      just the first**. Poll for review comments and address them as they land.
      This step ends when the PR is marked ready for review, or the user says it is done.
- [ ] 🛑 **6. MANUAL GATE: User Review.** **HARD STOP.**
      > The work is **blocked** on the author's review in the browser.
      > **Do not start Increment 2** until this PR is approved, marked ready for
      > review, or the user explicitly says to move on. A gate, not a formality —
      > no "proceeding while you look".

**Verify:** `{{EXACT_COMMAND_PROVING_IT_LANDED}}`

---

## Increment 2 of {{N}} — {{SHORT_NAME}}

**Delivers:** {{THE_SELF_CONTAINED_SLICE_IN_ONE_LINE}}
**Branch:** `{{branch-name}}` <!-- cut from the merged/approved result of Increment 1 -->

- [ ] **1. Write tests.** Add `{{test/path:test name}}` asserting {{THE_OBSERVABLE_BEHAVIOUR}}.
      Run `{{RELEVANT_TEST_COMMAND}}` — it **must fail** first.
- [ ] **2. Implement code.** {{THE_EDIT_IN_ONE_SENTENCE}} in `{{path}}`.
      Run `{{RELEVANT_TEST_COMMAND}}` — passes; refactor under green.
      Loop back to step 1 until this increment's slice is complete.
- [ ] **3. Code review.** `/code-review high`, then fix every finding.
- [ ] **4. Atomic commit (Tests + Code) and push.** Hook must pass on its own
      merits; no `--no-verify`. Done when the push succeeds.
- [ ] **5. Raise the draft PR.** `gh pr create --draft --reviewer {{GITHUB_USER}}`,
      then `gh pr view --web`. Address review comments until the PR is ready.
- [ ] 🛑 **6. MANUAL GATE: User Review.** **HARD STOP.**
      > **Do not start Increment 3** until this PR is approved or the user says so.

**Verify:** `{{EXACT_COMMAND_PROVING_IT_LANDED}}`

---

<!-- The pattern above repeats verbatim for Increments 3 … {{N}}: the same six steps,
     in the same order, each with its own Delivers line, branch, and Verify command.
     Write them out in full — never abbreviate to "as above". -->

## Increment {{N}} of {{N}} — {{SHORT_NAME}}

**Delivers:** {{THE_SELF_CONTAINED_SLICE_IN_ONE_LINE}}
**Branch:** `{{branch-name}}`

- [ ] **1. Write tests.** {{…}}
- [ ] **2. Implement code.** {{…}} (loop 1↔2 until the slice is done)
- [ ] **3. Code review.** `/code-review high`, fix findings.
- [ ] **4. Atomic commit (Tests + Code) and push.** {{…}}
- [ ] **5. Raise the draft PR.** {{…}} then `gh pr view --web`.
- [ ] 🛑 **6. MANUAL GATE: User Review.** **HARD STOP.**

**Verify:** `{{EXACT_COMMAND_PROVING_IT_LANDED}}`

---

## Done when

- [ ] `{{FULL_SUITE_COMMAND}}` green — the whole suite, not just the touched tests.
- [ ] `{{LINT_AND_FORMAT_GATE_COMMAND}}` clean.
- [ ] {{USER_VISIBLE_BEHAVIOUR}} confirmed by hand: `{{MANUAL_CHECK}}`.
- [ ] Every increment's PR marked ready for review and merged.

## Out of scope

<!-- Named up front so mid-execution scope creep is a visible contradiction, not a drift. -->

- {{ADJACENT_THING_NOT_DONE}} — {{WHY_NOT_NOW}}.
- {{ADJACENT_THING_NOT_DONE}} — {{WHY_NOT_NOW}}.
