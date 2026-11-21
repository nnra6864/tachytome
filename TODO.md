# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Save resolution presets
- `n` in the Resolution Presets list saves the current chain as a preset:
  a name checked like the parser does, then a file, an existing `.res` or
  a new one, the last used one first, then an optional description
  written as the comment above it.
- A name taken in that file asks to overwrite and replaces that line in
  place, a preset that would use itself is refused.
- Presets in the chain are saved by name, not expanded.

## 2. Save track presets
- The same as 1 for the Tracks Presets list and `.trk` files.
