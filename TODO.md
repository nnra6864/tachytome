# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

## 1. Installers
- `install.sh` (Linux, macOS) and `install.ps1` (Windows) in the repo root,
  served from GitHub raw and run with one line:
  `curl -fsSL https://raw.githubusercontent.com/nnra6864/tachytome/master/install.sh | sh`
  and `irm https://raw.githubusercontent.com/nnra6864/tachytome/master/install.ps1 | iex`.
- Finds the mpv config dir: `$MPV_HOME`, then `$XDG_CONFIG_HOME/mpv` or
  `~/.config/mpv` on Linux and macOS, the Flatpak dir
  `~/.var/app/io.mpv.Mpv/config/mpv` when that's the installed mpv,
  `portable_config` next to `mpv.exe` or `%APPDATA%\mpv` on Windows.
- Installs into `<mpv>/scripts/tachytome`:
  - git is the default: clones the GitHub repo and checks out the newest
    release tag, so Update and Version work through git.
  - git missing: offers installing it (package manager on Linux, `brew` on
    macOS, `winget` on Windows), and falls back to the GitHub archive of
    the newest release when declined or when it fails.
  - Already installed: says so and offers reinstalling, never deletes the
    user's config.
- Dependencies, each checked first, skipped when present, and asked before
  installing:
  - FFmpeg: pacman, apt, dnf or zypper with `sudo` on Linux, `brew` on
    macOS, `winget install -e --id Gyan.FFmpeg` on Windows.
  - Linux: `gio` or `trash-cli`, needed for trashing.
  - Warns when mpv itself isn't found.
- README: the one-liners become the main install method, the manual clone
  and submodule steps stay as alternatives.

## 2. Version tracking and the 1.0.0 -> 2.0.0 migration
- `src/version.lua` returns the running version, e.g. `"2.0.0"`, bumped on
  every release.
- A version file in the platform state dir: `$XDG_STATE_HOME/tachytome` or
  `~/.local/state/tachytome` on Linux, `~/Library/Application
  Support/tachytome` on macOS, `%LOCALAPPDATA%\tachytome` on Windows.
  Tachytome writes the running version to it on every start.
- On start, before writing the file:
  - File missing and the user config has 1.0.0 leftovers
    (`selected_keymap`, `keymap` blocks, `first_audio_only`, a config in
    `script-opts/`): came from 1.0.0, offer the migration.
  - File missing and no leftovers: first install or a new machine, just
    write the file.
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
- [?] Does the rest of the data dir (path history, recovery) move to the
  state dir too, or only the version file?
