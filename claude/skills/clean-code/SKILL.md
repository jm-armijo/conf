---
name: clean-code-principles
description: Enforces Clean Code principles for Ruby development. Use when writing, refactoring, or reviewing code.
---

# Clean Code Principles (Ruby)

Apply these rules strictly. If clarification or examples are needed, read the corresponding reference file.

1. **Naming Conventions** (`references/01_naming.rb`)
   - Use intention-revealing names.
   - Avoid disinformation.
   - Make meaningful distinctions.
   - Use pronounceable and searchable names.

2. **Functions** (`references/02_functions.rb`)
   - Small and do one thing (SRP).
   - Limit function arguments (0 or 1 preferred, 3+ requires justification).
   - Command Query Separation (CQS).
   - Avoid side effects.

3. **Comments** (`references/03_comments.rb`)
   - Explain "why", not "what".
   - Delete commented-out code.

4. **Formatting** (`references/04_formatting.rb`)
   - Vertical and horizontal proximity: variables declared close to usage, caller above callee.

5. **Objects and Data Structures** (`references/05_objects_and_data.rb`)
   - Hide internal structure (Law of Demeter).

6. **Error Handling** (`references/06_error_handling.rb`)
   - Prefer exceptions to error codes.
   - Don't pass or return null (`nil`).

7. **Boundaries** (`references/07_boundaries.rb`)
   - Encapsulate third-party boundaries.

8. **Classes** (`references/08_classes.rb`)
   - Single Responsibility Principle (SRP) and Cohesion.

9. **Unit Tests** (`references/09_unit_tests.rb`)
   - One assert per test / Single Concept.
   - F.I.R.S.T. Principles (Fast, Independent, Repeatable, Self-Validating, Timely).
