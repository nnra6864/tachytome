# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Space only where it makes sense in text input
- `ui_input.get_user_input` is the shared text input (quality, FPS, space
  replacement, path, effect params, queue "New Output Path").
- Add an option to it for whether space can be typed. Default: off.
- Turn it on for the output path (`actions.set_path`) and the queue's
  "New Output Path" (`queue_manager`), since that's also a path.
- With space off, space falls through to mpv (pause/play while typing),
  like in Go To.
- Effect params are fine without space: `bezier(0.22,1,0.36,1)` already
  parses without spaces.
- [?] Space Replacement: the conf says "set to ` ` (space) to preserve
  spaces", so taking space away there removes that from the prompt. Keep
  space on for that prompt, or give it a keyword like `space`?

## 2. Set In / Set Out prompts
- New menu actions `set_mark_in` / `set_mark_out`. They open the same input
  and parser as Go To, but set the mark instead of seeking.
- Bind them to `s-i` and `s-o` in the user's `nested` keymap
  (`~~/script-opts/tachytome.conf`, outside the repo).
- Conflict: `nested` currently binds `s` to `stats`, and that would shadow
  `s-i`/`s-o`.
  - [?] Where should `stats` move in `nested`?
- [?] Should relative input (`+5s`, `-10f`, `+2%`) count from the current
  playback position (like Go To) or from the mark's current value?
- [?] Should the prompt keep Go To's `i`/`o` shortcuts (e.g. copy In into
  Out), or have none?
- [?] Add these to the builtin/default keymap too, and if so on which keys?

## 3. Menu overhaul (replaces "keymap")
- The app only defines the available items and what they do: name, label
  translation key, `get_val`, action, `keep_open`. No order, keys, or
  separators in Lua (drop `registry` order/separators from `menu.lua` and the
  hardcoded `builtin` table from `keymap.lua`).
- The builtin config (repo `tachytome.conf`) is the single source of truth
  for the default menu: which items are shown, their order, key, label, and
  separators.
- A menu preset sets per item: shown or not, key/sequence, label (optional,
  overrides the translation).
- Layering: app item table -> translated labels -> builtin config -> user
  config.
- The "Keymap" concept is renamed to "Menu" and gets presets, chosen by an
  option plus a new menu item that switches preset at runtime.
- Separators: an empty line inside a `menu ... end` block. This works
  because Tachytome already reads the conf file line by line itself
  (`keymap.lua` `parse_conf`); `mp.options` doesn't see these blocks.
  Several empty lines in a row count as one separator. Comment-only lines
  are not separators.
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
- Existing features to keep: `base <preset>`, `none`/`ignore` to drop an
  item, flat one-line rebinds, nested sequences, shadowed-sequence warnings.
- [?] Old `keymap` blocks and `selected_keymap`: keep accepting them as
  aliases, or switch outright (your own conf uses `keymap nested`)?
- [?] Builtin vs user config: the user conf starts as a full copy of the
  builtin conf (`common.ensure_default_conf`), so today the builtin conf is
  never read once the user has a copy. For "builtin config overrides" the
  app has to read the repo `tachytome.conf` at runtime too. If both define
  `menu default`, does the user's block replace the builtin one, or patch it
  (like an implicit `base`)?
- [?] Same action listed twice (e.g. `i mark_in` and `x mark_in`): merge into
  one row `i,x -> Mark In` at the first position, like today?
- [?] Should the runtime menu-preset switch be written to the user conf, or
  last only for the session like other "dynamically set" options?

## 4. Translations + language option
- `language` option, plus a menu item to change it at runtime.
- Built into the project. Labels come from the active language, with English
  as the fallback for missing keys.
- Recommended format: one Lua file per language, e.g. `lang/en.lua`,
  `lang/sr.lua`, each returning a flat `key = "text"` table. Adding a
  language means dropping in one file. (A single file with every language
  works too, but gets long.)
- [?] Scope: only menu labels, or every UI string (prompts, tooltips,
  notifications, stats screen, Go To hints)?
- [?] Serbian: Latin (`sr-Latn`), Cyrillic (`sr`), or both?
- [?] Who writes the strings? AGENTS.md says no human-facing prose. Should I
  write the `en` file from the current strings and leave the others to you
  and your friends?
- [?] Should the runtime language switch be written to the user conf, or
  last only for the session?

## 5. Detect the language on first start
- mpv has no UI language option or property (`alang`/`slang`/`vlang` are
  media track preferences; `subs-match-os-language` uses the OS language
  internally but doesn't expose it). `slang`/`alang` could serve as a
  weak hint.
- OS detection is doable:
  - Linux/BSD: `LC_ALL` -> `LC_MESSAGES` -> `LANG` env vars.
  - macOS: env vars when launched from a terminal, otherwise
    `defaults read -g AppleLanguages` via subprocess.
  - Windows: no locale env var; needs a subprocess, e.g. PowerShell
    `(Get-UICulture).Name` (slow-ish, should run async).
- Fall back to English when nothing matches an available translation.
- [?] "First start" only (detect once while generating the user conf and
  write `language=<detected>` into it), or `language=auto` as the default,
  detected on every start?
