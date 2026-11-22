# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Save and reset settings from the menu
- A new `S` Save Settings item in Settings opens a choice: Save, Reset or
  Cancel, so changing options never needs editing a file.
- Save asks if you're sure, then writes the options changed from the menu
  this session through `write_option`, each to whichever file sets it, or
  the first enabled config when none does, like Menu and Language do now.
- Reset asks if you're sure, then puts `default.conf` back to the builtin
  one and reloads options and menus. It never touches `.res`, `.trk` or
  `.eff` files.
- [?] Save writes only the options changed from the menu, or every
  option that differs from the builtin default?
- [?] Reset only regenerates `default.conf`, or also offers to reset
  `tachytome.conf` to `configs=default` and delete the other configs,
  like the preset reset below?

## 2. Reset presets and effects to default
- `R` in the Preset Manager resets that kind, resolution, track or
  effect, and asks: reset only the default file, `default.res`,
  `default.trk` or `default.eff`, back to the builtin one, or also delete
  every other file of that kind, or Cancel.
- Selected effects and chains using a preset that's gone say so like a
  deleted preset does now.

## 3. Missing Serbian translations
- `lang/sr.lua` lacks the keys added since it was written, mostly Tracks:
  the `hint_tracks*`, `migrate_tracks*` and `tracks_*` strings,
  `key_position`, `key_rename`, `key_type` and `resolution_after`.
- Add them in the same order as `lang/en.lua`, untranslated keys fall
  back to English until then.
