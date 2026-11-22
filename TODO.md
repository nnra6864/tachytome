# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. default.conf is the base, user.conf holds your changes
- `default.conf` is an active copy of the builtin config, not commented
  out, always loaded first and never listed in `configs=`. Tachytome
  owns it and writes it again on every update, its header says changes
  go in `user.conf`.
- `user.conf` is loaded on top of it and holds only your changes, it
  replaces `tachytome.conf`. An optional `configs=` line in it loads
  extra configs like `work` or `stream`, lines above it apply before
  them, lines below override them. Configs in Settings edits that line.
- Migrating from 2.x moves the lines of `tachytome.conf` and any line
  uncommented in `default.conf` into `user.conf`, drops `default` from
  `configs=` and deletes `tachytome.conf`. Outdated keys are fixed in
  every `.conf` file, not just `default.conf`.

## 2. Save and reset settings from Settings
- A Save Settings item in Settings opens a choice: Save, Reset or
  Cancel, each asks if you're sure.
- Save writes the options changed from the menu to `user.conf`, Menu,
  Language and Version save there too.
- Reset empties `user.conf` but keeps its `configs=` line, then reloads
  options and menus. It never touches presets or effects.
- [?] Save writes only the options changed from the menu, or every
  option that differs from `default.conf`?

## 3. default.res, default.trk and default.eff are owned by Tachytome
- They're written again on every update like `default.conf`, and are
  loaded first, the rest alphabetically. A bare name picks the last
  file that defines it, so your own preset wins over a default one with
  the same name.
- Saving a preset or effect goes to `user.res`, `user.trk` or
  `user.eff`, or another of your files, never to `default.*`.
- Migrating from 2.x moves presets and effects that differ from that
  version's builtin ones into `user.*`.

## 4. Edits to default files are caught
- Tachytome remembers a hash of each `default.*` file it writes. One
  that doesn't match on start warns once and asks: move the changes to
  `user.*` or another file, undo them, or keep the file and stop
  updating it.

## 5. Reset presets and effects to default
- `R` in the Preset Manager resets that kind: empty `user.res`,
  `user.trk` or `user.eff`, or also delete every other file of that
  kind, or Cancel.
- Selected effects and chains using a preset that's gone say so like a
  deleted preset does now.

## 6. Missing Serbian translations
- `lang/sr.lua` lacks the keys added since it was written, mostly Tracks:
  the `hint_tracks*`, `migrate_tracks*` and `tracks_*` strings,
  `key_position`, `key_rename`, `key_type` and `resolution_after`.
- Add them in the same order as `lang/en.lua`, untranslated keys fall
  back to English until then.
