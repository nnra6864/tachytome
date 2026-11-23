# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings go in every language file, `lang/en.lua` and `lang/sr.lua`.

## 1. Reset presets and effects to default
- `R` in the Preset Manager resets that kind: empty `user.res`,
  `user.trk` or `user.eff`, which also drops its `default/name = on|off`
  lines, or also delete every other file of that kind, or Cancel.
- Selected effects and chains using a preset that's gone say so like a
  deleted preset does now.
