# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings are English only for now, translations wait for the last
item.

## 1. Settings Manager
- Replaces Configs in Settings: the configs list with `user` pinned on
  top, Tab enables or disables, Shift+Up/Down reorders, like now.
- New keys create, rename and delete a config, delete asks first.
- Enter opens the Settings Editor on the selected config.
- Save Settings and its Reset are removed, Reset becomes unset all in
  the editor. Menu, Language and Version keep saving to `user.conf`.

## 2. Settings Editor
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
