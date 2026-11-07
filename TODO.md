# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Several effects configs
- Effect preset files in `~~/script-opts/tachytome/` ending in `.eff` are
  auto detected, and their presets are merged.
- The generated builtin one becomes `default.eff` (migrated from
  `effects.conf` like the earlier config dir move).
- When two files define the same preset name, the last file
  (alphabetical) wins with a warning.
