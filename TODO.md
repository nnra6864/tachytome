# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Hidden menu items
- An item can be hidden from the menu list while its key(s) keep working.
- Syntax: a `hide` keyword like `add`, e.g. `hide s-s stats`; `key hide`
  as a patch hides an existing item.
- A hidden submenu still opens and shows its items; only its row is gone
  from the parent list.

## 2. Several configs
- `~~/script-opts/tachytome/` can hold several `.conf` files; the main
  `tachytome.conf` picks which ones are used with a list option, e.g.
  `configs=work,stream,!old`:
  - order matters: later configs override earlier ones
  - `!name` keeps a disabled config in the list so its position survives
  - lines in the main conf before the `configs=` line apply before the
    list, lines after it override the list
  - `.conf` files in the dir that aren't in the list are discovered and
    shown as disabled
- A `configs` item in the builtin `settings` submenu opens a list UI to
  enable/disable and reorder configs; changes are written back to the
  `configs=` line.
- Switching configs at runtime reloads options and menus; values computed
  at load (flash/start specs, theme) need to be recomputed.
- Runtime write-back (`selected_menu`, `language`) respects this order:
  it edits the line that currently wins, rather than always the main conf.

## 3. Several effects configs
- Effect preset files in `~~/script-opts/tachytome/` ending in `.eff` are
  auto detected, and their presets are merged.
- The generated builtin one becomes `default.eff` (migrated from
  `effects.conf` like the earlier config dir move).
- When two files define the same preset name, the last file
  (alphabetical) wins with a warning.
