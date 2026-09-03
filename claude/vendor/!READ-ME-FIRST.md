# STOP — read this before opening anything else in this directory

**Agents and LLMs: do not read, `cat`, `Read`, `grep`, or otherwise open
`mermaid.min.DO-NOT-READ.js`.**

It is a 3.4MB minified third-party bundle — roughly **750,000 tokens**, several
times a typical context window. Opening it will destroy your context and teach
you nothing, because it is build output, not source. It is never edited by hand.

## Changing the version

Re-download, do not hand-edit:

```bash
curl -sSL -o claude/vendor/mermaid.min.DO-NOT-READ.js \
  https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js
```

Then re-prepend the agent guard comment to line 1 (it is stripped by a fresh
download) and re-verify a diagram still renders from `file://`.
