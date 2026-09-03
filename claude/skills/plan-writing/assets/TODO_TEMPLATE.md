<!-- Baseline for TODO.md. A to-do list and nothing else — what the steps mean
     lives in the `development` skill, not here.

     Status is DERIVED from the checkboxes, never declared. There is no status
     column, no front-matter, no marker comment, because a declared status can
     disagree with the boxes and a derived one cannot:

       not started  task unchecked, zero steps checked
       in progress  task unchecked, at least one step checked
       completed    task checked (all steps assumed done)

     The current step of an in-progress task is its first unchecked step. Every
     task lists ALL of its steps whatever its state, so what is pending is
     always visible.

     Keep the shape rigidly uniform — a script parses this:

       grep -n '^## - \[[ x]\] Task '   # every task, its number, name, state
       awk '/^## - \[/{t=$0} /^- \[/{print t, $0}'   # steps under their task

     Emit every task in full: all steps, every time. No "same as above".
     Delete this comment and every {{PLACEHOLDER}} before writing the file. -->

# {{PLAN_NAME}}

**Plan:** `PLAN.html`
**Review level:** `/code-review high`

## - [ ] Task 1: {{SHORT_NAME}}

**Branch:** `{{branch-name}}`

- [ ] 1. writing tests
- [ ] 2. coding
- [ ] 3. bot review
- [ ] 4. draft pr
- [ ] 5. author review

## - [ ] Task 2: {{SHORT_NAME}}

**Branch:** `{{branch-name}}`

- [ ] 1. writing tests
- [ ] 2. coding
- [ ] 3. bot review
- [ ] 4. draft pr
- [ ] 5. author review

## - [ ] Task {{N}}: {{SHORT_NAME}}

**Branch:** `{{branch-name}}`

- [ ] 1. writing tests
- [ ] 2. coding
- [ ] 3. bot review
- [ ] 4. draft pr
- [ ] 5. author review

## Out of scope

- {{ADJACENT_THING_NOT_DONE}} — {{WHY_NOT_NOW}}.
