# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings go in every language file, `lang/en.lua` and `lang/sr.lua`.

## 1. The suffix only applies next to the source
- `suffix`, ` Remuxed` by default, is only added when the render goes to
  the source's own dir, where it would otherwise overwrite the source.

## 2. Builtin presets and effects are read in place
- `default.res`, `default.trk` and `default.eff` aren't generated anymore,
  the builtin ones are read from the script dir like the builtin config,
  loaded first, then your files alphabetically. A bare name picks the
  last file that defines it, so your own preset wins over a builtin one
  with the same name.
- Saving a preset or effect goes to `user.res`, `user.trk` or
  `user.eff`, or another of your files.
- Migrating from 2.x moves presets and effects in `default.*` that differ
  from that version's builtin ones into `user.*`, then deletes
  `default.*`.

## 3. Reset presets and effects to default
- `R` in the Preset Manager resets that kind: empty `user.res`,
  `user.trk` or `user.eff`, or also delete every other file of that
  kind, or Cancel.
- Selected effects and chains using a preset that's gone say so like a
  deleted preset does now.
