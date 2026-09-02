---
name: ui-separation
description: Requires user interfaces to be separated from business logic. Use when writing, refactoring, or reviewing any code that renders a UI - CLI output, TUI/curses, web/React, desktop, or templated HTML.
---

# UI / Business Logic Separation

**The rule:** presentation code and domain logic live in **separate modules**. A UI module
renders state and emits intent; it never owns rules. A domain module owns rules; it never
imports a rendering library.

## 1. Module boundary

Split every feature into at least two units:

- **Domain** — pure functions and data. No `print`, no `curses`, no DOM, no HTTP response
  objects, no framework imports, no colour codes, no string formatting meant for humans.
- **UI** — draws a value the domain produced and translates user input (keys, clicks,
  argv, form posts) into a domain call. Knows nothing about persistence, validation
  rules, pricing, state machines, or file paths.

A third **controller/adapter** unit may join them (wires I/O, sessions, devices). It stays
thin: sequencing and plumbing only, zero rules.

## 2. Dependency direction

Domain never imports UI. UI may import domain types. Enforce mechanically where possible:

```python
# recorder_state.py  - domain: no curses import anywhere in this file
def chunk_statuses(chunks, cursor, recorded): ...   # returns data, not colours

# recorder_ui.py     - UI: imports curses, receives the dict above
def draw(screen, view): ...                          # no CSV, no audio, no paths
```

If the domain module needs a rendering import to compile, the split is wrong.

## 3. Data crosses the boundary, not decisions

The domain returns **state**, the UI decides pixels. Return `status="recorded_selected"`,
never `colour=YELLOW`. Return `Decimal` totals, never `"$1,204.00"`. Return an error
value or exception type, never a user-facing sentence with markup.

## 4. Testability is the acceptance test

Domain logic must be fully testable with **no screen, no terminal, no browser, no
snapshot**. If asserting a business rule requires instantiating a view, mounting a
component, or driving a stub screen, the rule is in the wrong module — move it.

UI tests then only prove the view calls the toolkit as intended, on a stubbed/rendered
surface. They never assert business rules.

## 5. Refactoring an existing violation

1. Name the rule buried in the view (validation, calculation, state transition).
2. Extract it to a domain function taking plain arguments, returning plain data.
3. Leave the view calling that function, holding only layout and input mapping.
4. Move its tests off the view harness onto the extracted function.

Do this only for code already in scope of the current task — do not open a repo-wide
refactor unasked.

## 6. Review checklist

- [ ] Does a domain file import a UI toolkit? → violation.
- [ ] Does a view compute, validate, persist, or branch on business rules? → violation.
- [ ] Are human-facing strings/colours produced below the UI layer? → violation.
- [ ] Can every rule be tested headless? → if not, violation.
- [ ] Could the UI be replaced (curses → web, CLI → API) without touching domain files?
      → if not, violation.
