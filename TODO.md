# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Menu overhaul (replaces "keymap")
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
  saved to the user conf, the same way as the language (item 3).
- Separators: an empty line inside a menu block. This works because
  Tachytome already reads the conf file line by line itself (`keymap.lua`
  `parse_conf`). Several empty lines in a row count as one separator.
  Comment-only lines are not separators.

### Config directory
- User configs move from `~~/script-opts/` into `~~/script-opts/tachytome/`:
  - `~~/script-opts/tachytome.conf` -> `~~/script-opts/tachytome/tachytome.conf`
  - `~~/script-opts/tachytome-effects.conf` -> `~~/script-opts/tachytome/effects.conf`
- Future user files go in the same dir.
- `mp.options.read_options` only reads `~~/script-opts/<identifier>.conf`,
  and the identifier is also the `--script-opts=<identifier>-key=value`
  prefix, so don't point it into the subdir. Instead:
  - Tachytome parses the builtin and user conf files itself (needed anyway
    for the layering above).
  - Then it calls `read_options(opts, "tachytome")` as before. With no
    `~~/script-opts/tachytome.conf` left, this only applies
    `--script-opts=tachytome-...` command-line overrides, which keep working
    and stay on top.
- Migration on start:
  - If an old file exists and its new counterpart doesn't, move it into the
    new dir.
  - Move it unchanged; don't comment out an existing user config.
  - If both exist, use the new one and warn that the old one is ignored.
- Update every path that points at the old locations (`common.ensure_default_conf`,
  `state.lua`, `effects.lua`, the `effects_enabled` comment in the conf).

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
    old ones, shown as `i,x -> Mark In` like today
  - `key none` / `key ignore`: unbinds that key (the item disappears when no
    keys are left)
  - `key action` (action not in the base): appended at the end; to place it
    mid-menu, write the full menu without `base`
- `add` is a keyword rather than a `+` prefix because `+` is itself a
  bindable key.
- The same action may appear on several rows; each row is its own item.
  When a patch's `key action` matches an action that's on several rows, it
  rebinds the first one (in menu order) and warns that it's ambiguous.
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
- Menu blocks use braces, `menu X { ... }`, to match submenus (item 2); no
  `end`.
- Translated labels in the config: a label starting with `@key` uses that
  translation key, and the rest of the label is the fallback when the
  current language doesn't define it.
  ```
  s-i set_mark_in @set_in_short Set In
  s   mine        @my_stuff My Stuff {
  ```
  - A literal label starting with `@` is written as `@@`.
  - With no label at all, the item's or submenu's own translation key is
    used (as before).
  - `@key` only resolves against the built-in translation files; there are
    no user translation files. The built-in files should cover common words
    (e.g. `settings`), and anything else falls back to the label text. New
    keys come in through PRs.
  - Until item 3 exists there are no translation files; `@key` then always
    uses the fallback text, but the syntax is parsed now.

## 2. Submenus
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
- Patching from item 1 works across the whole tree, so `base` +
  `key action` finds the item even inside a submenu.
- Submenus coexist with dash sequences (`v-e`): sequences keep everything
  visible and highlight matches; submenus collapse into one row.
- The builtin menus put `language` and `menu_preset` into a `Settings`
  submenu. The human will reorganize the rest.

## 3. Translations + language option
- `language` option, default `auto` (item 4), plus a menu item to change it
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

## 4. Detect the language on every start
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
