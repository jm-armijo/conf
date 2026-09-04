---
name: task-status
description: Reports the status of the current plan's TODO.md as a single line - which tasks are done, which is in progress and on what step, how many remain. Use when asked where the project stands, what is left, what task or step is current, or for a status summary of the work at hand.
---

# Task Status

Report on `TODO.md` in the repository root. **Output exactly one line, and nothing else** —
no preamble, no headings, no bullets, no follow-up offer.

## The file is untracked but present — always check the filesystem

`TODO.md` is written by the `plan-writing` skill and **excluded locally via
`.git/info/exclude`, never committed**. So it is absent from `git status`, from
`git ls-files`, and from the repository snapshot in your context — while sitting in the
working directory the whole time. `.gitignore` does not mention it either.

**Never conclude the file is missing from anything git tells you, and never from
recollection.** A session-start `git status` showing no `TODO.md` is the expected state for
a file that exists. Only a failed filesystem check is evidence of absence:

```bash
ls TODO.md 2>/dev/null || echo "absent"
```

Run that (or read the file directly) every time this skill is invoked, before answering.
The no-file branch below is reachable *only* from that command failing.

## No TODO.md

Output only:

```
No TODO.md file exists.
```

Say nothing further — do not offer to create one, look elsewhere, or explain.

## With a TODO.md

Status is **derived from the checkboxes, never declared** — `TODO.md` carries no status
field, and any prose in it that claims a state is not evidence. Per task:

| State | Condition |
| --- | --- |
| completed | task heading checked (`## - [x] Task N: …`) |
| in progress | task unchecked, at least one step checked |
| not started | task unchecked, zero steps checked |

The **current step** is the first unchecked step of the first in-progress task; with no
in-progress task, the work sits at the first not-started task.

Parse it, don't skim it — the file's shape is uniform on purpose:

```bash
grep -n '^## - \[[ x]\] Task ' TODO.md            # tasks, numbers, names, states
awk '/^## - \[/{t=$0} /^- \[/{print t, $0}' TODO.md  # steps under their task
```

The one line names: how many tasks are done out of the total, the current task by number
and short name, and its current step. For example:

```
2/5 tasks done; Task 3 (session colour DB) in progress at step 2 coding.
```

When every task is checked, say so instead:

```
All 4 tasks complete.
```
