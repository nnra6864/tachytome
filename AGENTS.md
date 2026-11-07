# AGENTS.md — Tachytome

Instructions for any coding agent working in this repo.

## Project context
Tachytome is a keyboard-driven mpv script (Lua) for cutting video, with an
AV1/H265/lossless render pipeline. All keybinds live under a submap
("Tachytome Menu", default bind `t`), config is read from
`mpv/script-opts/tachytome.conf`, and there's a render queue concept for
managing multiple pending/active renders.

## Workflow rules
1. **One task at a time.** Implement exactly one TODO item (see `TODO.md`),
   then stop and wait for input before starting the next — even if the next
   item looks small or related — unless explicitly told to continue.
2. **Document your changes.** Update the README and the builtin config
   comments to cover what you add or change, rather than leaving `TODO:`
   comments for the human.
3. **Commit as you go.** Commit each self-contained step once it works,
   following the existing commit message style. Don't push.

## Technical directives
- **API lookups:** Do not guess standard APIs. Always look up latest info.
- **Code style:** Follow the style of the existing code — read the
  surrounding/neighbor files first and imitate them rather than importing
  your own conventions. Key points: 4-space indentation; `=` signs
  aligned within each contiguous block of assignments and within table
  constructors (pad every key in the block, including ones you add, to
  the longest one — re-align the block when it changes); `local M = {}`
  module pattern with `M.fn` public / `local fn` private; snake_case
  identifiers; double-quoted strings; `require 'x'` without parentheses;
  comments are essentially absent from the code — don't add any unless
  asked.
- **File editing:** Do not run Python, `sed`, or custom shell scripts to
  edit files. Use native file modification or write the updated file
  directly.
- **Environment:** Assume the current working directory is already the
  project root. Do not prepend `cd` to shell commands.
