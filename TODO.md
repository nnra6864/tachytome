# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Version tracking and the 1.0.0 -> 2.0.0 migration
- `src/version.lua` returns the running version, e.g. `"2.0.0"`, bumped on
  every release.
- A version file in the platform state dir: `$XDG_STATE_HOME/tachytome` or
  `~/.local/state/tachytome` on Linux, `~/Library/Application
  Support/tachytome` on macOS, `%LOCALAPPDATA%\tachytome` on Windows.
  Tachytome writes the running version to it on every start.
- On start, before writing the file and before `ensure_main_conf` moves
  anything:
  - File missing, `script-opts/tachytome.conf` exists and there's no
    `script-opts/tachytome/` subdir: a pre-1.0.0 install (today's
    master), offer the migration.
  - File missing otherwise: first install or a new machine, just write the
    file.
  - File older than the running version: run the migrations after it.
- Migrations are an ordered list of `{ version, detect, apply }`; the
  2.0.0 one moves the config out of `script-opts/`, renames
  `selected_keymap` -> `selected_menu` and `first_audio_only` ->
  `combined_audio_only`, and converts `keymap` blocks to `menu` syntax.
  The scattered compat code (`aliases` in `src/conf.lua`, the config move
  in `ensure_main_conf`, the `first_audio_only` menu alias, the recovery
  fallback) moves into it.
- One dialog on the first start after the jump: what changed, Migrate
  (backs the config up to `.bak` first), Show changes, Skip (not asked
  again for this version).
- Update reads the target version before installing and warns when it
  crosses a major version, e.g. `2.4.1 -> 3.0.0`.
- Path history and render recovery move from the data dir to the state
  dir too, moving existing files over on the first start.
