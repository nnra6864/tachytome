# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Preset descriptions on hover
- The `#` lines right above a preset, up to a blank line, are its
  description, a bare `#` is an empty line in it, a grouped preset shows
  the group's comment.
- Shown line by line, dim, under the title for the row under the cursor in
  the Resolution and Tracks Presets lists, the Preset Manager and the
  Effects List. `#` and one space are stripped, the rest is kept.

## 2. Multi-line descriptions
- Shift+Enter adds a new line in inputs that allow it, only the
  description step of saving a preset for now.
- Each line is saved as `# line`, an empty one as `#`, the replace hint
  shows the current description over several lines.
