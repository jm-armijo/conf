<!-- Baseline for TODO.md. One increment = one behaviour = one failing test.
     Delete this comment and every {{PLACEHOLDER}} before writing the file. -->

# {{PLAN_NAME}}

**Outcome:** {{ONE_LINE}}
**Plan:** `PLAN.html`

## Increment 1 — {{BEHAVIOUR_IN_FIVE_WORDS}}

- [ ] **Red.** Add `{{test/path.bats:test name}}` asserting {{THE_OBSERVABLE_BEHAVIOUR}}.
      Run `{{TEST_COMMAND}}` — it must fail with {{THE_EXPECTED_FAILURE_MESSAGE}}.
      A test that passes before the change tests nothing; if it passes, the
      assertion is wrong, not the code.
- [ ] **Green.** {{THE_MINIMAL_EDIT_IN_ONE_SENTENCE}} in `{{path}}`.
      Run `{{TEST_COMMAND}}` — passes.
- [ ] **Refactor.** {{WHAT_TO_TIDY_OR_"none — the green edit is already minimal"}}.
      Run `{{FULL_SUITE_COMMAND}}` — no regressions.

**Verify:** `{{COMMAND}}`

## Increment 2 — {{BEHAVIOUR}}

- [ ] **Red.** …
- [ ] **Green.** …
- [ ] **Refactor.** …

**Verify:** `{{COMMAND}}`

## Done when

- [ ] `{{FULL_SUITE_COMMAND}}` green.
- [ ] {{LINT_OR_FORMAT_GATE}} clean.
- [ ] {{USER_VISIBLE_BEHAVIOUR_CONFIRMED_BY_HAND}}.

## Out of scope

- {{ADJACENT_THING_DELIBERATELY_NOT_DONE_AND_WHY}}
