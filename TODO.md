# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Keyframe interval
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
