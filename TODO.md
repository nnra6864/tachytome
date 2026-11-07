# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Translations + language option
- `language` option, default `auto` (item 2), plus a menu item to change it
  at runtime, placed in the builtin menus' `settings` submenu.
- Every UI string is translatable: menu labels, submenu labels, prompts,
  tooltips, notifications, stats screen, Go To hints.
- Format: one Lua file per language, e.g. `lang/en.lua`, `lang/sr.lua`,
  each returning a flat `key = "text"` table. English is the fallback for
  missing keys.
- Only the `en` file gets written; other languages are translated by the
  human.
- The `en` file covers the builtin submenu ids (`video`, `audio`,
  `settings`); until then a submenu without a label shows its prettified id.
- Setting the language manually from the menu writes it to the user conf:
  - if a `language=` line exists, replace it in place
  - otherwise insert the `language` entry, with its comment block from the
    builtin conf, at the very top of the user conf
- The same write-back is used for the menu preset (`selected_menu`).

## 2. Detect the language on every start
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

## 3. Shorter displayed paths
- Paths shown in the UI (menu `Path` value, prompts, notifications, stats)
  replace the home dir prefix with `~`, e.g. `/home/nn/Videos` -> `~/Videos`.
- Home dir: `HOME` on Linux/BSD/macOS, `USERPROFILE` on Windows (shown as
  `~\Videos`).
- Display only; paths passed to ffmpeg and written to files stay absolute.
- [?] Also shorten paths under the source file's dir, e.g. `./Repo/Funny/`?

## 4. Hidden menu items
- An item can be hidden from the menu while its key(s) keep working.
- [?] Syntax: a `hide` keyword like `add`, e.g. `hide s-s stats`, and
  `key hide` as a patch to hide an existing item?
- [?] Does a hidden submenu still open (showing its items), and does
  hiding apply to dash sequence highlighting?

## 5. Several configs
- `~~/script-opts/tachytome/` can hold several config files; the main
  `tachytome.conf` picks which ones are used.
- Order matters: options set in the main conf before the include apply
  first, the included file overrides them, and lines after it override
  the included file.
- Runtime write-back (`selected_menu`, `language`) respects this order:
  it edits the line that currently wins, rather than always the main conf.
- [?] Syntax for picking a config, e.g. `include work.conf`, and whether
  several may be active at once.
- [?] Should switching configs at runtime be a menu item (like the menu
  preset)?

## 6. Several effects configs
- Effect preset files in `~~/script-opts/tachytome/` ending in `.eff` are
  auto detected, and their presets are merged.
- The generated builtin one becomes `default.eff` (migrated from
  `effects.conf` like the earlier config dir move).
- [?] What happens when two files define the same preset name: last file
  (alphabetical) wins with a warning?
