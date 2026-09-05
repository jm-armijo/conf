---
name: clean-code-principles
description: Enforces Clean Code principles for Ruby development. Use when writing, refactoring, or reviewing code.
---

# Clean Code Principles (Ruby)

Apply these rules strictly. If clarification or examples are needed, read the corresponding reference file.

1. **Naming Conventions** (`references/01_naming.md`)
   - Use intention-revealing names.
   - Avoid disinformation.
   - Make meaningful distinctions.
   - Use pronounceable and searchable names.

2. **Functions** (`references/02_functions.md`)
   - Small and do one thing (SRP).
   - Limit function arguments (0 or 1 preferred, 3+ requires justification).
   - Command Query Separation (CQS).
   - Avoid side effects.

3. **Comments** (`references/03_comments.md`)
   - **Default to zero comments.** Rename/extract before explaining.
   - Explain "why", not "what" — never restate the name below it.
   - No header summaries, section banners, or per-class doc lines.
   - Delete commented-out code.

4. **Formatting** (`references/04_formatting.md`)
   - Vertical and horizontal proximity: variables declared close to usage, caller above callee.

5. **Objects and Data Structures** (`references/05_objects.md`)
   - Hide internal structure (Law of Demeter).

6. **Error Handling** (`references/06_errors.md`)
   - Prefer exceptions to error codes.
   - Don't pass or return null (`nil`).

7. **Boundaries** (`references/07_boundaries.md`)
   - Encapsulate third-party boundaries.

8. **Classes** (`references/08_classes.md`)
   - Single Responsibility Principle (SRP) and Cohesion.

9. **Unit Tests** (`references/09_tests.md`)
   - One assert per test / Single Concept.
   - F.I.R.S.T. Principles (Fast, Independent, Repeatable, Self-Validating, Timely).
