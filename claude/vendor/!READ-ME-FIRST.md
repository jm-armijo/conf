# STOP — read this before opening anything else in this directory

**Agents and LLMs: do not read, `cat`, `Read`, `grep`, or otherwise open
`mermaid.min.DO-NOT-READ.js`.**

It is a 3.4MB minified third-party bundle — roughly **750,000 tokens**, several
times a typical context window. Opening it will destroy your context and teach
you nothing, because it is build output, not source. It is never edited by hand.

## What it is

Vendored [Mermaid](https://mermaid.js.org) 11, the diagram renderer used by
`PLAN.html` (see the `plan-writing` skill). It lives here rather than in the
skill's `assets/` directory precisely so that nothing ever points an agent at
it: `assets/` is documented as "templates the skill reads", and this is not a
template.

## How to use it

Reference it **by path only**, and the path must be **absolute and already
expanded**:

```html
<script src="/Users/<you>/.claude/vendor/mermaid.min.DO-NOT-READ.js"></script>
```

The `<you>` above is illustrative — **HTML does not expand `~`**, so a tilde
here loads nothing and every diagram renders as raw text with no console error.
This is why `UI_TEMPLATE.html` carries a `{{VENDOR_DIR}}` placeholder that is
substituted with a resolved absolute directory: `PLAN.html` is written into
whatever repo is being planned in, so a relative path cannot resolve either.

The **classic (IIFE) build is required** and the ESM build will not work.
`PLAN.html` is opened from `file://`, where an ESM `import` — even of a local
file — fails with "Failed to fetch dynamically imported module". A plain
`<script src>` is exempt from those module CORS rules. This was verified in
headless Chrome, both directions; do not "modernise" it to an ESM import.

## Changing the version

Re-download, do not hand-edit:

```bash
curl -sSL -o claude/vendor/mermaid.min.DO-NOT-READ.js \
  https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js
```

Then re-prepend the agent guard comment to line 1 (it is stripped by a fresh
download) and re-verify a diagram still renders from `file://`.
