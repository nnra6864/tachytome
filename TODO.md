# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Preset manager
- `m` in the Resolution and Tracks Presets lists and in the Effects list
  opens a manager of every preset of that kind, disabled ones included,
  grouped by file, numbered and searchable.
- Tab/0-9 enables or disables a preset, writing only that line of the
  file.
- `d` deletes a preset and its own comment above it, a notification
  offers `u` to undo for a few seconds, undo doesn't overwrite a file
  that changed since.
- A file left with no presets, enabled or disabled, is deleted, the
  defaults still regenerate when a kind has no files.
- The line-preserving file editing is its own module, so saving settings
  from the UI can use it later.

## 2. Save resolution presets
- `n` in the Resolution Presets list saves the current chain as a preset:
  a name checked like the parser does, then a file, an existing `.res` or
  a new one, the last used one first, then an optional description
  written as the comment above it.
- A name taken in that file asks to overwrite and replaces that line in
  place, a preset that would use itself is refused.
- Presets in the chain are saved by name, not expanded.

## 3. Save track presets
- The same as 2 for the Tracks Presets list and `.trk` files.
