<!-- Baseline for TODO.md — the execution state machine.
     One increment = one behaviour = one failing test.
     Emit every increment in full: all five steps, every time. No "same as above".
     Delete this comment and every {{PLACEHOLDER}} before writing the file. -->

# {{PLAN_NAME}}

**Outcome:** {{ONE_LINE_OUTCOME}}
**Plan:** `PLAN.html` — architecture, data flow, boundaries crossed.
**Increments:** {{N}} total.

## Progress

<!-- Every increment, one row. Status: `todo` / `in progress` / `awaiting review` / `done`.
     Update the row the moment the increment's state changes — this table is what the
     user reads first, and a stale row is worse than no table. -->

| # | Increment | Delivers | Status |
|---|-----------|----------|--------|
| 1 | {{BEHAVIOUR_IN_FIVE_WORDS}} | {{THE_ONE_OBSERVABLE_BEHAVIOUR}} | todo |
| 2 | {{BEHAVIOUR_IN_FIVE_WORDS}} | {{THE_ONE_OBSERVABLE_BEHAVIOUR}} | todo |
| … | … | … | todo |
| {{N}} | {{BEHAVIOUR_IN_FIVE_WORDS}} | {{THE_ONE_OBSERVABLE_BEHAVIOUR}} | todo |

---

## Increment 1 of {{N}} — {{BEHAVIOUR_IN_FIVE_WORDS}}

**Delivers:** {{THE_SINGLE_OBSERVABLE_BEHAVIOUR_IN_ONE_LINE}}

- [ ] **1. Write tests.** Add `{{test/path:test name}}` asserting {{THE_OBSERVABLE_BEHAVIOUR}}.
      Run `{{TEST_COMMAND}}` — it **must fail** with {{THE_EXPECTED_FAILURE_MESSAGE}}.
      A test that passes before the implementation tests nothing; if the red step is
      green, the assertion is wrong, not the code.
- [ ] **2. Implement code.** {{THE_MINIMAL_EDIT_IN_ONE_SENTENCE}} in `{{path}}`.
      Run `{{TEST_COMMAND}}` — passes. Minimal means minimal: anything the test does
      not force is the next increment, not this one.
- [ ] **3. Atomic commit (Tests + Code).** One commit carrying both.
      `git commit -m "{{IMPERATIVE_SUBJECT_LINE}}"`
      Never split tests and implementation across commits — one commit keeps every
      point in history independently verifiable and makes a revert a single operation.
- [ ] **4. Update Draft PR.** `git push` — then confirm the draft PR reflects this
      increment ({{PR_REF_OR_"open it on the first increment"}}).
- [ ] 🛑 **5. MANUAL GATE: User Review.** **HARD STOP.**
      > **Do not start Increment 2.** Wait for the user to review and explicitly
      > approve. This is a gate, not a formality — no "proceeding while you look".

**Verify:** `{{EXACT_COMMAND_PROVING_IT_LANDED}}`

---

## Increment 2 of {{N}} — {{BEHAVIOUR_IN_FIVE_WORDS}}

**Delivers:** {{THE_SINGLE_OBSERVABLE_BEHAVIOUR_IN_ONE_LINE}}

- [ ] **1. Write tests.** Add `{{test/path:test name}}` asserting {{THE_OBSERVABLE_BEHAVIOUR}}.
      Run `{{TEST_COMMAND}}` — it **must fail** with {{THE_EXPECTED_FAILURE_MESSAGE}}.
      If this increment needs more than one failing test to express, it is too large — split it.
- [ ] **2. Implement code.** {{THE_MINIMAL_EDIT_IN_ONE_SENTENCE}} in `{{path}}`.
      Run `{{TEST_COMMAND}}` — passes.
- [ ] **3. Atomic commit (Tests + Code).** One commit carrying both.
      `git commit -m "{{IMPERATIVE_SUBJECT_LINE}}"`
- [ ] **4. Update Draft PR.** `git push` — draft PR now carries Increments 1–2.
- [ ] 🛑 **5. MANUAL GATE: User Review.** **HARD STOP.**
      > **Do not start Increment 3.** Wait for explicit user approval.

**Verify:** `{{EXACT_COMMAND_PROVING_IT_LANDED}}`

---

<!-- The pattern above repeats verbatim for Increments 3 … {{N}}: the same five steps,
     in the same order, each with its own Delivers line and Verify command.
     Write them out in full — never abbreviate to "as above". -->

## Increment {{N}} of {{N}} — {{BEHAVIOUR_IN_FIVE_WORDS}}

**Delivers:** {{THE_SINGLE_OBSERVABLE_BEHAVIOUR_IN_ONE_LINE}}

- [ ] **1. Write tests.** {{…}}
- [ ] **2. Implement code.** {{…}}
- [ ] **3. Atomic commit (Tests + Code).** {{…}}
- [ ] **4. Update Draft PR.** {{…}}
- [ ] 🛑 **5. MANUAL GATE: User Review.** **HARD STOP.**

**Verify:** `{{EXACT_COMMAND_PROVING_IT_LANDED}}`

---

## Done when

- [ ] `{{FULL_SUITE_COMMAND}}` green — the whole suite, not just the touched tests.
- [ ] `{{LINT_AND_FORMAT_GATE_COMMAND}}` clean.
- [ ] {{USER_VISIBLE_BEHAVIOUR}} confirmed by hand: `{{MANUAL_CHECK}}`.
- [ ] PR marked ready for review (out of draft).

## Out of scope

<!-- Named up front so mid-execution scope creep is a visible contradiction, not a drift. -->

- {{ADJACENT_THING_NOT_DONE}} — {{WHY_NOT_NOW}}.
- {{ADJACENT_THING_NOT_DONE}} — {{WHY_NOT_NOW}}.
