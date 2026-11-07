# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Space only where it makes sense in text input
- `ui_input.get_user_input` is the shared text input (quality, FPS, space
  replacement, path, effect params, queue "New Output Path").
- Add an option to it for whether space can be typed. Default: off.
- Turn it on for:
  - the output path (`actions.set_path`)
  - the queue's "New Output Path" (`queue_manager`)
  - Space Replacement (`actions.set_space_replacement`), which must accept a
    literal space character
- With space off, space falls through to mpv (pause/play while typing),
  like in Go To.
- Effect params are fine without space: `bezier(0.22,1,0.36,1)` already
  parses without spaces.

## 2. Mark-relative time input (`~`)
- In the shared Go To parser, `~` marks a time as relative to a mark
  instead of to the current playback position:
  - `+5s` / `-1m30s` / `+10f` / `+2%`: relative to the current position (as
    today)
  - `~+5s` / `~-10f` / `~+2%`: relative to the mark
- Works in Go To and in Set In / Set Out (item 3).
- In Set In it means the In mark; in Set Out, the Out mark.
- [?] In Go To there are two marks. Which one does `~` use? Options:
  - `~` = In and `~~` = Out
  - separate characters, e.g. `[+5s` (In) / `]+5s` (Out)
  - `~` unsupported in Go To
- [?] Bare `~` with no offset: the mark itself (a no-op in Set In/Out,
  "jump to mark" in Go To)?

## 3. Set In / Set Out prompts
- New menu actions `set_mark_in` / `set_mark_out`. They open the same input
  and parser as Go To, but set the mark instead of seeking.
- No `i`/`o` shortcuts in these prompts.
- In the user's `nested` keymap (`~~/script-opts/tachytome.conf`, outside
  the repo):
  - bind `s-i` -> `set_mark_in`, `s-o` -> `set_mark_out`
  - move `stats` from `s` to `s-s`
- [?] Add these to the builtin/default menu too, and if so on which keys?

## 4. Menu overhaul (replaces "keymap")
- The app only defines the available items and what they do: name, label
  translation key, `get_val`, action, `keep_open`. No order, keys, or
  separators in Lua (drop `registry` order/separators from `menu.lua` and the
  hardcoded `builtin` table from `keymap.lua`).
- The builtin config (repo `tachytome.conf`) is the single source of truth
  for the default menu: which items are shown, their order, key, label, and
  separators. Both it and the user conf are read at runtime.
- A menu preset sets per item: shown or not, key/sequence, label (optional,
  overrides the translation).
- Layering: app item table -> translated labels -> builtin config -> user
  config.
- The user config always overrides the builtin one. A user `menu X` block
  replaces the builtin `menu X` entirely; no implicit patching.
  - [?] Keep `base <preset>` as an explicit opt-in for building on another
    preset?
- Switch from `keymap` to `menu` outright, with no aliases for the old
  `keymap` blocks or `selected_keymap`. Update the user's own conf to the
  new syntax.
- A new menu item switches the menu preset at runtime.
  - [?] Session-only, or saved to the user conf like the language (item 5)?
- Separators: an empty line inside a `menu ... end` block. This works
  because Tachytome already reads the conf file line by line itself
  (`keymap.lua` `parse_conf`). Several empty lines in a row count as one
  separator. Comment-only lines are not separators.
- An action listed twice shows up as two rows.
- Draft syntax:
  ```
  selected_menu=nested

  menu nested
      i   mark_in
      o   mark_out
      s-i set_mark_in  Postavi početak

      v-e encoder
  end
  ```
  The label is everything after the action, spaces allowed; `#` can't
  appear in a label because it starts a comment.
- Existing features to keep: `none`/`ignore` to drop an item, flat
  one-line rebinds, nested sequences, shadowed-sequence warnings.
- [?] Generated user conf: today `common.ensure_default_conf` copies the
  whole builtin conf on first start. A full copy includes `menu default`, so
  it would always override the builtin menu, and builtin menu updates would
  never reach the user. That defeats the single source of truth. Should the
  generated user conf instead be empty or minimal (e.g. a short header),
  with the repo conf serving as the reference to copy from?

## 5. Translations + language option
- `language` option, default `auto` (item 6), plus a menu item to change it
  at runtime.
- Every UI string is translatable: menu labels, prompts, tooltips,
  notifications, stats screen, Go To hints.
- Format: one Lua file per language, e.g. `lang/en.lua`, `lang/sr.lua`,
  each returning a flat `key = "text"` table. English is the fallback for
  missing keys.
- Only the `en` file gets written; other languages are translated by the
  human.
- Setting the language manually from the menu writes it to the user conf:
  - if a `language=` line exists, replace it in place
  - otherwise insert the `language` entry, with its comment block from the
    builtin conf, at the very top of the user conf

## 6. Detect the language on every start
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
