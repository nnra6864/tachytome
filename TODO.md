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

## 2. Mark-relative time input
- In the shared Go To parser, a leading mark character makes the time
  relative to a mark instead of to the current playback position:
  - `+5s` / `-1m30s` / `+10f` / `+2%`: relative to the current position (as
    today)
  - `[+5s` / `[-10f` / `[+2%`: relative to the In mark
  - `]+5s` / `]-10f` / `]+2%`: relative to the Out mark
  - a bare `[` or `]` means that mark itself
- Works in every prompt that uses the parser: Go To, Set In, Set Out
  (item 3). This allows things like Set Out `[+30s` (a 30s clip from In).
- `[`/`]` replaces the earlier `~` idea: it covers both marks, works the
  same in every prompt, and reads like "start/end".
- [?] Confirm `[`/`]` over `~`.

## 3. Set In / Set Out prompts
- New menu actions `set_mark_in` / `set_mark_out`. They open the same input
  and parser as Go To, but set the mark instead of seeking.
- No `i`/`o` shortcuts in these prompts.
- User's `nested` keymap (`~~/script-opts/tachytome.conf`, outside the
  repo):
  - bind `s-i` -> `set_mark_in`, `s-o` -> `set_mark_out`
  - move `stats` from `s` to `s-s`
- The builtin `nested` keymap must match the user's `nested` keymap exactly.
- Builtin `default` keymap: `ctrl+i` -> `set_mark_in`,
  `ctrl+o` -> `set_mark_out` (`I`/`O` are taken).
  - Note: in terminal-only output (`--vo=tct`) `ctrl+i` arrives as `TAB`;
    the normal video window is fine.

## 4. Menu overhaul (replaces "keymap")
- The app only defines the available items and what they do: name, label
  translation key, `get_val`, action, `keep_open`. No order, keys, or
  separators in Lua (drop `registry` order/separators from `menu.lua` and the
  hardcoded `builtin` table from `keymap.lua`).
- The builtin config (repo `tachytome.conf`) is the single source of truth
  for the default menus: which items are shown, their order, key, label, and
  separators. Both it and the user conf are read at runtime.
- Layering: app item table -> translated labels -> builtin config -> user
  config.
- Switch from `keymap` to `menu` outright, with no aliases for the old
  `keymap` blocks or `selected_keymap`. Update the user's own conf to the
  new syntax.
- A new menu item switches the menu preset at runtime. A manual switch is
  saved to the user conf, the same way as the language (item 6).
- Separators: an empty line inside a menu block. This works because
  Tachytome already reads the conf file line by line itself (`keymap.lua`
  `parse_conf`). Several empty lines in a row count as one separator.
  Comment-only lines are not separators.

### Generated user conf
- On first start, `common.ensure_default_conf` generates the user conf as
  a copy of the builtin conf with every line commented out. That keeps it
  discoverable without overriding anything; the user uncomments only what
  they change.
- Downside: the commented copy can drift from newer builtin versions. That's
  harmless, since it's only comments.

### Overrides and patching
- A user `menu X` block with the same name as a builtin one replaces it
  entirely.
- `base <preset>` builds a menu on top of another preset; inside it, lines
  patch the base:
  - `key action` (action already in the base): rebinds that item; its old
    key(s) are replaced and its position stays the same
  - `add key action`: adds an extra key to the existing item, keeping the
    old ones
  - `key none` / `key ignore`: unbinds that key (the item disappears when no
    keys are left)
  - `key action` (action not in the base): appended at the end; to place it
    mid-menu, write the full menu without `base`
- Each action appears at most once per menu tree, so "rebind action" is
  never ambiguous. More keys for one item go through `add`, and show as
  `i,x -> Mark In` like today. This replaces the earlier "an action listed
  twice shows twice".
- `add` is a keyword rather than a `+` prefix because `+` is itself a
  bindable key.
- Existing features to keep: flat one-line rebinds on the active menu
  (same patch rules), nested dash sequences, shadowed-sequence warnings.

### Draft syntax
```
selected_menu=nested

menu nested {
    base default

    s-i set_mark_in
    add x mark_in
    t none
}

menu mine {
    i   mark_in
    o   mark_out
    s-i set_mark_in  Postavi početak

    v-e encoder
}
```
- The label is optional, and is everything after the action, spaces allowed.
  `#` can't appear in a label because it starts a comment.
- [?] Switch the outer block from `menu X ... end` to `menu X { ... }` so it
  matches submenus (item 5)?

## 5. Submenus
- A menu line can open a submenu: one row in the parent
  (`s -> Settings`); pressing its key shows only that submenu's items.
- Submenus can nest. `ESC` goes back one level (as with sequences today).
  The title shows the path, e.g. `< Tachytome > Settings >`.
- Draft syntax:
  ```
  s settings {
      l language
      m menu_preset
  }
  ```
  - `settings` is the submenu's id: the translation key for its label and
    the name used for patching (`x settings` rebinds the submenu's key).
  - An optional label goes between the id and `{`, like for items:
    `s settings Podešavanja {`.
  - A line ending in `{` opens a submenu; `}` alone on a line closes it.
- Patching from item 4 works across the whole tree: actions are unique per
  menu tree, so `base` + `key action` finds the item even inside a
  submenu.
- [?] Should submenus coexist with dash sequences (`v-e`)? Sequences keep
  everything visible and highlight matches; submenus collapse into one row.
  Recommendation: keep both.
- [?] Should the builtin menus put `language` and `menu_preset` into a
  `Settings` submenu?

## 6. Translations + language option
- `language` option, default `auto` (item 7), plus a menu item to change it
  at runtime.
- Every UI string is translatable: menu labels, submenu labels, prompts,
  tooltips, notifications, stats screen, Go To hints.
- Format: one Lua file per language, e.g. `lang/en.lua`, `lang/sr.lua`,
  each returning a flat `key = "text"` table. English is the fallback for
  missing keys.
- Only the `en` file gets written; other languages are translated by the
  human.
- Setting the language manually from the menu writes it to the user conf:
  - if a `language=` line exists, replace it in place
  - otherwise insert the `language` entry, with its comment block from the
    builtin conf, at the very top of the user conf
- The same write-back is used for the menu preset (`selected_menu`).

## 7. Detect the language on every start
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
