# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Detect the language on every start
- `language=auto` (the default) detects the language on every start; any
  other value forces that language.
- mpv has no UI language option or property (`alang`/`slang`/`vlang` are
  media track preferences; `subs-match-os-language` uses the OS language
  internally but doesn't expose it).
- OS detection:
  - Linux/BSD: `LC_ALL` -> `LC_MESSAGES` -> `LANG` env vars.
  - macOS: env vars when launched from a terminal, otherwise
    `defaults read -g AppleLanguages` via subprocess.
  - Windows: no locale env var; needs a subprocess, e.g. PowerShell
    `(Get-UICulture).Name` (slow-ish, should run async).
- Fall back to English when nothing matches an available translation.

## 2. Shorter displayed paths
- The menu shows the shortest possible form of a path, since full paths
  make the menu far too wide:
  - under the source file's dir: `./Repo/Funny/MyClip.mkv`
  - under the home dir: `~/Videos/...` (`HOME` on Linux/BSD/macOS,
    `USERPROFILE` on Windows, shown as `~\Videos`)
  - pick whichever of the two is shorter when both apply
- The path input prompt shows the fully expanded path below the input,
  updating as the user types.
- Display only; paths passed to ffmpeg and written to files stay absolute.

## 3. Hidden menu items
- An item can be hidden from the menu list while its key(s) keep working.
- Syntax: a `hide` keyword like `add`, e.g. `hide s-s stats`; `key hide`
  as a patch hides an existing item.
- A hidden submenu still opens and shows its items; only its row is gone
  from the parent list.

## 4. Several configs
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

## 5. Several effects configs
- Effect preset files in `~~/script-opts/tachytome/` ending in `.fx` are
  auto detected, and their presets are merged.
- The generated builtin one becomes `default.fx` (migrated from
  `effects.conf` like the earlier config dir move).
- When two files define the same preset name, the last file
  (alphabetical) wins with a warning.
