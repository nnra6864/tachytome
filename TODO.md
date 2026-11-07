# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Cursor movement in text inputs
- Applies to every text input: the generic input (`ui_input`, e.g. Path,
  Quality) and the Go To prompt (`ui_goto`).
- Keys:
  - Left/Right move the cursor by one character.
  - Home/End jump to the start/end of the text.
  - ctrl+Left/ctrl+Right jump by word.
  - ctrl+Backspace deletes the previous word.
  - Backspace deletes before the cursor, typed text is inserted at it.
- Word boundaries stop at whitespace and separators like `-`, `_`, `/`,
  `\`, `.`, `,`, `:`, `;` and brackets, the way shells and editors do,
  e.g. ctrl+Backspace on `~/Videos/my_clip|` leaves `~/Videos/my_`.
- Block cursor that doesn't shift the text:
  - ASS has no per-character background, so the overlay draws two
    events on top of each other: the normal line with the character
    under the cursor replaced by `█` in the cursor color, then the same
    line fully transparent except that character, drawn on top.
  - Works because the OSD font is monospace; at the end of the text the
    block sits after the last character.
  - New theme options in the builtin conf: `cursor_color` (block,
    defaults to the `value_color` value) and `cursor_text_color`
    (character on the block, defaults to black).
- History (Up/Down, ctrl+j/k) puts the cursor at the end of the recalled
  entry.

## 2. Keyframe interval
- New `keyframe_interval` option, empty by default, meaning the encoder's
  own default (no `-g` passed), which is today's behavior.
- Value is a frame count, e.g. `120`, or seconds with an `s` suffix, e.g.
  `2s`, converted to frames using the output FPS (respecting the FPS
  override).
- Passed as `-g` to every encoder (libsvtav1, libx265, libx264, nvenc,
  qsv); ignored by Lossless Cut since it stream copies.
- Menu item `keyframes` showing the current value (or the encoder default
  label when empty): `v-k` in the default menu's Video submenu, `k` in the
  simple menu. Set for the session like Quality, not written back.
