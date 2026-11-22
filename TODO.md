# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings are English only for now, translations wait for the last
item.

## 1. Settings Editor
- Enter in the Settings Manager opens it on the selected config, saving
  the manager's list first.
- Edits one config file. Lists every option from the builtin config,
  the hovered one's comment block shows dim under the list like a
  preset's description. No menus, only option values.
- A row is set in this file, shown bright, or inherited, shown dim with
  the value it gets from `default.conf` and the other configs.
- Editing a row sets it in this file: toggles for yes/no options, the
  existing pickers where there's one, e.g. encoder, quality,
  resolution and tracks, a text input otherwise. A key unsets it, so it
  inherits again, and a key unsets every row.
- Load current sets every option whose live value differs from what
  this file would inherit, so changes made from the menu can be kept.
- Edits only change the file, never the running session.
- Saving writes only the rows set in this file, keeping the file's
  other lines and comments. Saving a config that isn't enabled in
  `configs=` asks to add it to `user.conf`.
- Esc with unsaved changes asks: Save, Discard or Cancel.

## 2. default.res, default.trk and default.eff are owned by Tachytome
- They're written again on every update like `default.conf`, and are
  loaded first, the rest alphabetically. A bare name picks the last
  file that defines it, so your own preset wins over a default one with
  the same name.
- Saving a preset or effect goes to `user.res`, `user.trk` or
  `user.eff`, or another of your files, never to `default.*`.
- Migrating from 2.x moves presets and effects that differ from that
  version's builtin ones into `user.*`.

## 3. Edits to default files are caught
- Tachytome remembers a hash of each `default.*` file it writes. One
  that doesn't match on start warns once and asks: move the changes to
  `user.*` or another file, undo them, or keep the file and stop
  updating it.

## 4. Reset presets and effects to default
- `R` in the Preset Manager resets that kind: empty `user.res`,
  `user.trk` or `user.eff`, or also delete every other file of that
  kind, or Cancel.
- Selected effects and chains using a preset that's gone say so like a
  deleted preset does now.

## 5. Missing Serbian translations
- `lang/sr.lua` lacks the keys added since it was written, mostly Tracks:
  the `hint_tracks*`, `migrate_tracks*` and `tracks_*` strings,
  `key_position`, `key_rename`, `key_type` and `resolution_after`.
- Add them in the same order as `lang/en.lua`, untranslated keys fall
  back to English until then.
