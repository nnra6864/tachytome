# Tachytome

Tachos (τάχος) – Speed<br>
Tome &nbsp;&nbsp;(τομή) &nbsp;– Cut

Keyboard Driven, AV1/H265/H264/Lossless, MPV Video Cutter.

<a href="https://youtu.be/PoyvYFPhrfI">
  <img src="assets/tachytome.webp" width="100%">
</a>

*Click the image to view a quick showcase of Tachytome capabilities.*

## Table of Contents

- [Why Tachytome?](#why-tachytome)
- [Installation](#installation)
  - [Installer](#installer)
  - [Dependencies](#dependencies)
  - [Clone](#clone)
  - [Submodule](#submodule)
  - [Upgrading](#upgrading)
- [Usage](#usage)
  - [Quickstart](#quickstart)
  - [Keymap](#keymap)
  - [Config](#config)
  - [Recovery](#recovery)
  - [Go To](#go-to)
  - [Resolution](#resolution)
  - [Effects](#effects)
  - [Path](#path)
- [Contributing](#contributing)
- [Donations](#donations)
- [AI](#ai)

## Why Tachytome?

Cutting clips was always an exhausting chore for me.<br>
I would clip something, navigate to it, open a video editor/cutting utility, drag and drop or paste the path, and so on.<br>
Now consider the fact I have ~1TB of clips.<br>
I built Tachytome to make cutting clips fun, easy and fast.<br>
You run into a good clip, and Tachytome is right there, ready to cut the important part with the settings of your choice.<br>
No more copying paths, no more external software with poor UX, it's all there, right in your video player.

## Installation

### Installer

The installer puts Tachytome in your mpv scripts dir and offers installing what's missing.

- Linux, Mac
```sh
curl -fsSL https://raw.githubusercontent.com/nnra6864/tachytome/master/install.sh | sh
```

- Windows (Powershell)
```sh
irm https://raw.githubusercontent.com/nnra6864/tachytome/master/install.ps1 | iex
```

- Installs into the dir mpv reads its config from, `$MPV_HOME`, `$XDG_CONFIG_HOME/mpv` or `~/.config/mpv`, the Flatpak dir when that's your only mpv, and `portable_config` next to `mpv.exe`, `$MPV_HOME` or `%APPDATA%/mpv` on Windows.
- Clones the release marked Latest on GitHub with git, offering to install git when it's missing, and downloads the release archive from GitHub otherwise.
- Offers installing FFmpeg, and gio or trash-cli on Linux, with your package manager, `brew` on Mac or `winget` on Windows.
- When Tachytome is already installed, it asks before reinstalling and moves the current install next to the scripts dir, your config is never touched.

To install manually instead, get the dependencies and clone the repo or add it as a submodule.

### Dependencies

- [ffmpeg](https://ffmpeg.org/) - needed for all the video operations.
- [gio](https://www.gtk.org/docs/architecture/glib)/[trash](https://github.com/andreafrancia/trash-cli) - needed on Linux for trashing files.

*gio is preinstalled on most distributions*

- Arch
```sh
sudo pacman -S ffmpeg
```

- Mac
```sh
brew install ffmpeg
```

- Windows
```sh
winget install -e --id Gyan.FFmpeg
```

### Clone

You may clone the repo directly to your config:

- Unix
```sh
git clone https://git.nnstdios.com/nnra6864/tachytome ~/.config/mpv/scripts/tachytome
```

- Windows (Powershell)
```sh
git clone https://git.nnstdios.com/nnra6864/tachytome "$env:APPDATA/mpv/scripts/tachytome"
```

### Submodule

If you are source controlling your dotfiles, consider adding Tachytome as a submodule:

- Unix
```sh
git submodule add ../../nnra6864/tachytome ~/.config/mpv/scripts/tachytome
```

- Windows (Powershell)
```sh
git submodule add ../../nnra6864/tachytome "$env:APPDATA/mpv/scripts/tachytome"
```

> [!NOTE]
> `../../` in the link makes git use the same server as your root repo.<br>
> For example, if your dotfiles are hosted on `https://github.com/name/dotfiles`, double `../` will make it go up twice in the URL, ending up with `https://github.com/`, and then appending `nnra6864/tachytome` to that, resulting in `https://github.com/nnra6864/tachytome`

### Upgrading

Tachytome remembers the version it last ran in the state dir, see [Recovery](#recovery).<br>
When a new version changes the config format, the first start after updating shows what will change and asks:

- **Migrate** converts your config, keeping the old files next to it with a `.bak` extension.
- **Skip, start fresh** uses the new defaults, keeping the old files as `.bak` too.
- **Later** asks again on the next start, using the defaults until then.

Updates that cross a major version, e.g. `2.4.1 -> 3.0.0`, are pointed out before installing.

#### 1.0.0 -> 2.0.0

- `mpv/script-opts/tachytome.conf` becomes `mpv/script-opts/tachytome/default.conf`, sourced by a new `tachytome.conf`.<br>
  Only options you changed from the 1.0.0 defaults are kept, `first_audio_only` is renamed to `combined_audio_only`, and options that no longer exist are dropped.
- Everyone moves to the new `default` menu, `selected_keymap` is dropped.<br>
  Your own keymaps become menus, e.g. `keymap mine ... end` turns into `menu mine { ... }`, with `ignore` becoming `none` and `base builtin` or `base default` becoming `base simple`, `base nested` becoming `base default`.<br>
  Keymaps named like a builtin menu get an `old_` prefix, and flat rebinds like `keymap r render` become `menu r render`.
- `mpv/script-opts/tachytome-effects.conf` is replaced by `.eff` files in `mpv/script-opts/tachytome/`, effects you added or changed go to `custom.eff`.
- Path history, stats and render queues move from `~/.local/share/tachytome` to `~/.local/state/tachytome` on Linux.
- A git install that 1.0.0's updater left on `master` switches to the latest release when that's the same commit.

## Usage

Tachytome is entirely keyboard driven.<br>
All the binds are isolated into a submap (Tachytome menu), which you can access by pressing `t` by default.<br>
This is done to avoid global bind conflicts.

### Quickstart

- `t` to open the Tachytome menu.
- `g` and type in `10` to go to 10 seconds of your video.
- `i` to mark in.
- `g` and type in `90%` to go to 90% of your video.
- `o` to mark out.
- `g` and `i`/`o` to make sure mark in and out are good.
- `p` to set the name of your video.
- `Enter` to start the render.
- `r` then `q` to access the render queue.

### Keymap

| Keybind | Action | Description              |
|---------|--------|--------------------------|
| t       | Menu   | Open the Tachytome menu. |
| nil     | Go To  | Open the Go To menu.     |
| nil     | Trash  | Trash current file.      |

Go To and Trash hide the Tachytome menu while they're open and bring it back where you left it once they close.<br>
They do nothing while another list, prompt or dialog is open, close it first.

#### Menu

The `default` menu groups related items into the Video, Audio and Settings submenus.<br>
Keys like `s-i` are pressed one after another, `s` then `i`.<br>
Esc steps back out of a partially typed key or a submenu, the title shows where you are, e.g. `< Tachytome / Video >`.<br>
The `simple` menu keeps every item on a single level, switch to it with `s-s` `m` or `selected_menu=simple`.

| Keybind | Action            | Description                                                                                  |
|---------|-------------------|----------------------------------------------------------------------------------------------|
| g       | Go To             | Go to a precise location in the video.<br>Learn more about [Go To](#go-to).                  |
| i       | Mark In           | Mark the start of the video.                                                                 |
| o       | Mark Out          | Mark the end of the video.                                                                   |
| s-i     | Set In            | Type in the Mark In, same input as [Go To](#go-to).                                          |
| s-o     | Set Out           | Type in the Mark Out, same input as [Go To](#go-to).                                         |
| <hr>    | <hr>              | <hr>                                                                                         |
| v       | Video             | Open the [Video](#video) submenu.                                                            |
| a       | Audio             | Open the [Audio](#audio) submenu.                                                            |
| T       | Tracks            | Pick the tracks kept in the output.<br>Learn more about [Tracks](#tracks-list).              |
| e       | Effects           | Select the effects applied to the output.<br>Learn more about [Effects](#effects).           |
| <hr>    | <hr>              | <hr>                                                                                         |
| p       | Path              | Set Output path.<br>Learn more about [Path](#path).                                          |
| _       | Space Replacement | Set the character to replace spaces with.                                                    |
| t       | Trash Source      | Toggle trashing of the source file on render completion.                                     |
| <hr>    | <hr>              | <hr>                                                                                         |
| Enter   | Render            | Start the render of the output file.                                                         |
| r-q     | Render Queue      | Open the render queue menu.                                                                  |
| r-p     | Pause Render      | Pause the current render and render queue.<br>Can only pause the render queue on Windows.    |
| d       | Trash Source Now  | Trash the source file.                                                                       |
| <hr>    | <hr>              | <hr>                                                                                         |
| s-s     | Settings          | Open the [Settings](#settings) submenu.                                                      |
| Esc     | Close             | Close the currently active menu.                                                             |

##### Video

| Keybind | Action       | Description                                                                                                   |
|---------|--------------|---------------------------------------------------------------------------------------------------------------|
| e       | Encoder      | Set the video encoder.                                                                                        |
| q       | Quality      | Set the video encoder quality parameter.                                                                      |
| f       | FPS          | Set the FPS of the video.                                                                                     |
| k       | Keyframes    | Set the keyframe interval, e.g. `120` frames or `2s`.<br>Empty matches the source, shown like `2s`.           |
| p       | Preset       | Set the video encoder preset parameter.                                                                       |
| r       | Resolution   | Set the output resolution.<br>Learn more about the [Resolution List](#resolution-list) and [Resolution](#resolution). |
| l       | Lossless Cut | Toggle the lossless cut option.                                                                               |
| a       | Accurate Cut | Toggle accurate cut.<br>Makes cuts millisecond precise, but may cause a slight delay before rendering starts. |

##### Audio

| Keybind | Action           | Description                                                                         |
|---------|------------------|-------------------------------------------------------------------------------------|
| e       | Audio Encoder    | Set the audio encoder, `copy` keeps the source audio.                               |
| b       | Audio Bitrate    | Set the bitrate, e.g. `128k`, shows the source or `Best`.<br>Empty resets it.       |
| c       | Combine Audio    | Toggle the combine audio option.                                                    |
| o       | Combined Only    | Keep only the combined track, dropping the tracks it was mixed from.                |

##### Audio Export

End the [Path](#path) with an audio extension to export audio only, e.g. `clip.opus` or `clip.mp3`.<br>
Supported formats are `mka`, `opus`, `ogg`, `oga`, `m4a`, `mp3`, `aac`, `flac` and `wav`, video and subtitles are dropped.<br>
With the `copy` encoder the audio is copied when the format can hold it, otherwise it's re-encoded with the format's own codec, e.g. Opus for `.opus`, AAC for `.m4a`.<br>
The typed format also wins over a picked Audio Encoder it can't hold, e.g. the `mp3` encoder with `clip.opus` gives Opus.<br>
Audio is only re-encoded when needed: a codec the format can't hold, audio effects, the combined track, a picked encoder or a set bitrate.<br>
Re-encoded audio keeps the source bitrate when the codec stays the same, otherwise it uses the highest quality, 256k per channel for Opus and AAC, 320k for MP3 and quality 10 for Vorbis.<br>
`opus`, `mp3`, `aac`, `flac` and `wav` hold a single track, the first selected one, or the combined one with Combine Audio.<br>
Dropping every video track in the [Tracks](#tracks-list) list switches the default name to an audio format, so it's never re-encoded just to fit.<br>
A single kept track uses its own format, e.g. `.opus` for Opus, `.m4a` for AAC or `.flac` for FLAC, several tracks use `.mka`, Matroska for audio.<br>
Pick which audio tracks are exported in the [Tracks](#tracks-list) list.

##### Settings

| Keybind | Action   | Description                                                                                                         |
|---------|----------|---------------------------------------------------------------------------------------------------------------------|
| s       | Stats    | Toggle the Tachytome stats overlay.                                                                                 |
| m       | Menu     | Switch the menu, saved to your config.<br>Learn more about [Custom Menus](#custom-menus).                           |
| c       | Configs  | Enable, disable and reorder extra configs.<br>Learn more about [Configs](#configs).                                 |
| l       | Language | Switch the UI language, saved to your config.<br>Learn more about [Translations](#translations).                    |
| v       | Version  | Pick the version Update installs, saved to your config as `version`.                                                |
| U       | Update   | Update Tachytome to the picked version using git, falls back to the GitHub archive.<br>Restart mpv after updating.  |

The `version` option takes:
- `latest`, the default, the release marked Latest, or the highest version tag when there's no release.
- A branch name, e.g. `master`, following that branch.
- A full or partial version, pinning the highest version tag it matches, e.g. `3` for the newest 3.x.x, `2.1` for the newest 2.1.x, or `1.2.5` for exactly 1.2.5.

Version tags look like `v1.2.5` or `1.2.5`, others like `v2.0-rc1` are skipped.<br>
Version lists `latest`, the branches and every release with its partial versions.<br>
A git clone reads them from the remote of the current branch, or `origin` when it's detached at a release, and asks that remote's host which release is Latest.<br>
GitHub and Forgejo/Gitea hosts are supported, other hosts fall back to the highest version tag.<br>
Without git, everything comes from the GitHub repo.<br>
Updating through git switches the checkout to the branch, or detaches it at the release.

#### Render Queue

| Keybind | Action        | Description                                                                                |
|---------|---------------|--------------------------------------------------------------------------------------------|
| Enter   | Pause Render  | Pauses the current render and render queue.<br>Can only pause the render queue on Windows. |
| p       | Change Path   | Change output path.                                                                        |
| d       | Delete        | Deletes the item from the render queue.                                                    |

#### Go To Prompt

| Keybind | Action    | Description                        |
|---------|-----------|------------------------------------|
| i       | Go To In  | Go to Mark In, no Enter required.  |
| o       | Go To Out | Go to Mark Out, no Enter required. |
| Enter   | Go To     | Go to the typed in location.       |

#### Text Inputs (Path, Quality, Go To etc.)

| Keybind              | Action      | Description                             |
|----------------------|-------------|-----------------------------------------|
| Left/Right           | Move        | Move the cursor by one character.       |
| ctrl+Left/ctrl+Right | Move Word   | Move the cursor by one word.            |
| Home/End             | Start/End   | Jump to the start or end of the text.   |
| Backspace            | Delete      | Delete the character before the cursor. |
| ctrl+Backspace       | Delete Word | Delete the word before the cursor.      |

Inputs show the current value and a hint on the accepted format below the prompt.<br>
Submitting an empty input resets to the default where there is one, e.g. the source FPS for FPS or the default path for Path, otherwise it keeps the current value.<br>
Esc closes any prompt or dialog without changing anything.

Words end at whitespace and separators like `-`, `_`, `/`, `\`, `.`, `,`, `:`, `;` and brackets, e.g. ctrl+Backspace on `~/Videos/my_clip` leaves `~/Videos/my_`.<br>
The cursor is a bar by default, set `cursor_style` to `bar`, `underline` or `block` to change it.<br>
It's drawn above the text, the block also redraws the character under it on top, in the inverse of the cursor color by default.<br>
See the `cursor_` options in the [builtin config](./tachytome.conf) for its colors and glow.

#### Path

| Keybind     | Action   | Description                                              |
|-------------|----------|----------------------------------------------------------|
| Up/ctrl+k   | Previous | Select previous item in history, cursor goes to its end. |
| Down/ctrl+j | Next     | Select next item in history, cursor goes to its end.     |

#### Lists (Render Queue, Preset etc.)

| Keybind     | Action        | Description              |
|-------------|---------------|--------------------------|
| Up/k        | Navigate Up   | Navigates to item above. |
| Down/j      | Navigate Down | Navigates to item below. |
| 1-9         | Select        | Selects the item number. |

Inputs like the Path prompt use ctrl+k/ctrl+j instead, since plain letters are typed into the input.

#### Effects List

| Keybind | Action | Description                                 |
|---------|--------|---------------------------------------------|
| Enter   | Toggle | Select or deselect the preset.              |
| d       | Edit   | Edit the duration and params of the preset. |
| Esc     | Close  | Close the list.                             |

#### Resolution List

| Keybind      | Action    | Description                                                              |
|--------------|-----------|--------------------------------------------------------------------------|
| Enter        | Edit      | Toggle Resolution, type the whole chain or replace the selected layer.   |
| a            | Add       | Add layers after the selected one, or at the end.                        |
| m            | Mode      | Pick the layer's mode from a list, Default follows `resolution_mode`.    |
| s            | Scaler    | Pick the layer's scaler from a list, Default follows the scaler options. |
| d            | Delete    | Delete the layer.                                                        |
| Shift+Up/K   | Move Up   | Move the layer up, before the one above.                                 |
| Shift+Down/J | Move Down | Move the layer down, after the one below.                                |
| Esc          | Close     | Close the list.                                                          |

The title shows the source and output size, each layer shows its mode, the scaler it uses and the size it goes from and to.<br>
Modes and scalers set on the layer are highlighted, the rest come from the defaults, `-` means it doesn't apply.<br>
The inputs show the resulting size while typing and share a history kept across restarts, an input can hold several layers, e.g. `5:4 crop 0.5x`.<br>
Setting a chain turns Resolution on, an empty Chain keeps the source.

#### Tracks List

| Keybind   | Action     | Description                                    |
|-----------|------------|------------------------------------------------|
| a         | Pick Audio | Show the audio tracks.                         |
| v         | Pick Video | Show the video tracks.                         |
| 1-9       | Toggle     | Keep or drop the track with that number.       |
| Enter     | Toggle     | Keep or drop the track under the cursor.       |
| Esc       | Close      | Close the list.                                |

Each track shows its number, title, on/off state and its codec, channels or size and language.<br>
Tracks past the 9th have no number key, reach them with Up/Down and toggle them with Enter.<br>
The list opens on audio, set `tracks_type=video` to open on video instead.<br>
`audio_tracks` and `video_tracks` pick the tracks kept by default for every loaded file, `all`, a list like `1,3`, or empty for none.<br>
Only the file's own tracks are listed, external audio files loaded into mpv aren't part of the render.<br>
Combine Audio mixes only the selected ones, dropping every video track renders audio only.

#### Configs List

| Keybind      | Action    | Description                                 |
|--------------|-----------|---------------------------------------------|
| Enter        | Toggle    | Enable or disable the config.               |
| Shift+Up/K   | Move Up   | Move the config up, before the one above.   |
| Shift+Down/J | Move Down | Move the config down, after the one below.  |
| Esc          | Close     | Save the changes to your config and reload. |

### Config

You can configure Tachytome with the `mpv/script-opts/tachytome/default.conf` file.<br>
It should get automatically generated on the first launch, with every line commented out.<br>
Uncomment and change only what you need, everything else uses the [builtin config](./tachytome.conf).<br>
The builtin config contains detailed explanations of all the settings, I would highly suggest reading it.

`mpv/script-opts/tachytome/tachytome.conf` is generated too, containing only `configs=default`, which picks the [configs](#configs) that get used.

A deleted `default.conf` is generated again on start when `default` is enabled in `configs`, or when there are no other `.conf` files next to `tachytome.conf`.

> [!NOTE]
> Coming from 1.0.0, which used `mpv/script-opts/tachytome.conf`? See [Upgrading](#upgrading).

To access exposed Tachytome functions, add the following to your `mpv/input.conf`:
```
t script-binding tachytome/menu
g script-binding tachytome/goto
d script-binding tachytome/trash
```
Replace `t`, `g` and `d` with keys of your choice.

#### Configs

`mpv/script-opts/tachytome/` can hold more `.conf` files next to `default.conf`, e.g. `work.conf` and `stream.conf`, picked with the `configs` option in `tachytome.conf`:
```
configs=default,work,stream,!old
```

- Configs are named without `.conf`, later ones override earlier ones.
- `!name` disables a config while keeping its place in the list.
- Lines in `tachytome.conf` above the `configs=` line apply before the configs, lines below it override them.
- Configs can set options and define [menus](#custom-menus), `configs` itself only works in `tachytome.conf`.
- `.conf` files in the dir that aren't listed show up as disabled.
- Switch them from the menu with `c` in Settings, which writes the `configs=` line and reloads options and menus.<br>
  Options changed from the menu during the session are reset to the config values on reload.
- Switching the menu, language or version from the menu saves it to whichever file sets it, e.g. `work.conf` when it's the one that wins.<br>
  When no file sets it yet, it goes to the first enabled config.

#### Custom Menus

The Tachytome menu is fully configurable through menus in your configs, e.g. `default.conf`.<br>
Pick the active one with `selected_menu`, or switch it from the menu with `m`.

```
menu mine {
    i   mark_in
    o   mark_out
    s-i set_mark_in Set In

    v-e encoder
}
```

| Line                      | Meaning                                                                         |
|---------------------------|---------------------------------------------------------------------------------|
| `menu <name> {`           | Starts a menu, closed with `}`.                                                 |
| `<keys> <action>`         | Bind a key to an action. Chain keys with `-`, e.g. `v-e`, to make nested binds. |
| `<keys> <action> <label>` | Same, with a custom label.                                                      |
| `hide <keys> <action>`    | Bind a key to an action without showing it in the menu list.                    |
| `<keys> <id> {`           | Starts a [submenu](#submenus), closed with `}`.                                 |
| empty line                | Separator.                                                                      |

Hidden items keep working from their keys.<br>
A hidden submenu, e.g. `hide s-s settings {`, still opens and shows its items, only its row is gone from the parent list.

Labels starting with `@` are [translation](#translations) keys, e.g. `@menu_set_mark_in Set In`, with the rest used as the fallback.<br>
Use `@@` for a label that starts with `@`.

##### Submenus

A line ending in `{` opens a submenu, its items go inside and it's closed with `}`:

```
menu mine {
    i mark_in

    v video {
        e encoder
        q quality
    }
    s-s settings Options {
        m menu_preset
        x extras {
            s stats
        }
    }
}
```

- The key opens the submenu, Esc goes back to the parent.
- The id names the submenu, e.g. `video`, so it can be patched and [translated](#translations) through `submenu_<id>`.
- An optional label after the id, e.g. `Options`, replaces the translation, use `@key Fallback` to keep it translatable.
- Submenus nest, the menu title shows the path, e.g. `< Tachytome / Options / Extras >`, joined with `menu_path_separator`.
- Submenus without any bound items are dropped from the list.

##### Base

Use `base` to build a menu on top of another one, the lines below then patch it:

```
menu nested {
    base default

    s-i set_mark_in
    add x mark_in
    t none
    s-s hide
}
```

| Line                  | Meaning                                                             |
|-----------------------|---------------------------------------------------------------------|
| `base <name>`         | Start from another menu instead of an empty one.                    |
| `<keys> <action>`     | Rebind an item, it keeps its place.<br>New items go at the end.     |
| `add <keys> <action>` | Add another key to an item, shown as `i,x -> Mark In`.              |
| `<keys> none`         | Unbind a key, `ignore` works too.                                   |
| `<keys> hide`         | Hide the item bound to a key from the list, its keys keep working.  |

- `hide` also works on patch lines and together with `add`, e.g. `add hide x mark_in` adds a key and hides the item.
- Patching an action finds it anywhere in the tree, e.g. `Q quality` rebinds Quality inside the Video submenu, keeping it there.
- `<keys> <id> {` patches an existing submenu, rebinding its key, the lines inside patch its items:
  ```
  v-v video {
      Q quality
      x none
  }
  ```
- `<keys> none` and `<keys> hide` only affect keys of the level they are on, use a submenu block to reach keys inside it.
- When an action appears more than once in the tree, the first one is patched with a warning.
- A menu with the same name as a builtin one replaces it.
- A single line `menu <keys> <action>` outside of any block patches whichever menu is selected.
- If a key is bound on its own, any nested binds starting with it are unreachable and will be ignored with a warning.

Actions are named after menu items in snake_case, e.g. `mark_in`, `goto`, `render_queue`, `trash_source_now`.<br>
See the `default` menu in the [builtin config](./tachytome.conf) for the full list.

#### Translations

Every UI string comes from a language file in the [`lang`](./lang) dir, e.g. `lang/en.lua`.<br>
Ships with English (`en`) and Serbian (`sr`, Latin script).<br>
Pick one with the `language` option, or switch it from the menu with `l`, which saves it to your config.<br>
`auto`, the default, detects the system language on every start, any other value forces that language.

- Linux/BSD read the `LC_ALL`, `LC_MESSAGES` and `LANG` env vars, in that order.
- macOS reads the same env vars when launched from a terminal, otherwise `defaults read -g AppleLanguages`.
- Windows asks PowerShell for `(Get-UICulture).Name` in the background, the UI switches once it answers.
- A detected `sr_RS.UTF-8` or `sr-Latn-RS` tries the most specific language file first, e.g. `sr_RS`, `sr-RS`, then `sr`.
- When nothing matches an available language, English is used.
- The menu shows the detected language next to `auto`, e.g. `auto (sr)`.

A language file returns a flat table of keys and their text:

```lua
return {
    menu_mark_in     = "Mark In",
    submenu_settings = "Settings",
    value_set        = "{label}: {value}"
}
```

- Keys missing from a language fall back to [English](./lang/en.lua), so a translation can be partial.
- `{name}` placeholders get replaced with values, keep them as they are, their order can change.
- Submenus are labeled by `submenu_<id>`, e.g. `submenu_video`, or their capitalized id when there's no such key, e.g. `my_stuff` shows as `My stuff`.
- Menu item labels, `menu_<action>`, are reused as the titles of the screens they open and in their notifications, e.g. `Quality: 30`.
- Key tooltips are built from `key_hint`, e.g. `{keys} to {action}`, and one `key_<action>` per action, e.g. `key_navigate`.
- To add a language, copy `lang/en.lua` to `lang/<code>.lua` and translate the text.

### Recovery

Tachytome gracefully handles crashes and accidental closes.<br>
Render queues are stored as files tied to the mpv PID, in the state dir: `$XDG_STATE_HOME/tachytome` or `~/.local/state/tachytome` on Linux, `~/Library/Application Support/tachytome` on Mac and `%LOCALAPPDATA%/tachytome` on Windows.<br>
The path history and the installed version live there too.<br>
Every time you start a new mpv instance, the script checks if any of these are present without an active mpv instance.<br>
It then asks you whether you want to recover, discard or ignore the queue.

### Go To

Tachytome includes a really powerful Go To implementation.<br>
On top of many input types, it also supports relative jumps.

#### Prefix

You can prefix `+` or `-` to make go to relative to the current time.

#### HH:MM:SS.MS

This is arguably the most versatile format as you can do `30` to go to 30 seconds, but also `1:2.50` to go to 1 minute 2 seconds 500 milliseconds.

#### Suffix

This is a convenient format to jump across minutes, hours etc.<br>
Instead of having to type `1:0`, you simply type `1m` to go to 1 minute.

| Suffix | Value       |
|--------|-------------|
| ms     | millisecond |
| s      | second      |
| m      | minute      |
| h      | hour        |
| d      | day         |
| f      | frame       |
| %      | percent     |

#### In/Out

Press `i` or `o` inside the Go To prompt to instantly jump to Mark In or Mark Out.<br>
Their current values are listed right below the input.

#### Examples

| Input  | Goes To             |
|--------|---------------------|
| `+30`  | 30 seconds ahead    |
| `2:0`  | 2 minutes           |
| `1:13` | 1 minute 13 seconds |
| `3m`   | 3 minutes           |
| `50ms` | 50 milliseconds     |
| `-60f` | 60 frames back      |
| `5%`   | 5%                  |

### Resolution

The `resolution` option sets the output resolution as a chain of layers applied in order, empty keeps the source.<br>
Change it on the fly in the [Resolution List](#resolution-list), Video > Resolution.<br>
It's applied while `resolution_enabled` is on, which stays on across files like Effects, and is incompatible with Lossless Cut, turning either on turns the other off.<br>
Each size token starts a new layer, a mode or scaler word right after it applies to that layer.

| Token          | Layer                                               |
|----------------|-----------------------------------------------------|
| `0.5x`, `50%`  | Multiplier, keeps the aspect.                       |
| `1920x1080`    | Box, how the frame gets into it is set by the mode. |
| `1280w`        | Width, keeps the aspect.                            |
| `720h`, `720p` | Height, keeps the aspect.                           |
| `4:3`          | Aspect, keeps the res, the box depends on the mode. |

An aspect is the largest box of it inside the frame for `cover` and `crop`, the smallest one around it for `fit`, and keeps the height for `stretch`.

| Mode      | Description                                                                 |
|-----------|-----------------------------------------------------------------------------|
| `fit`     | Scales the frame to fit inside, pads the rest with `pad_color`. Default.    |
| `cover`   | Scales the frame to cover it, crops what's left over from the center.       |
| `stretch` | Scales to the exact size, ignoring the aspect.                              |
| `crop`    | Cuts the center out without scaling, can't be bigger than the frame.        |

Scalers are `lanczos`, `spline`, `bicubic`, `area`, `bilinear`, `neighbor`, `fast_bilinear`, `bicublin`, `gauss` and `sinc`.<br>
Layers without one use `scaler_down` when they shrink the frame and `scaler_up` when they grow it, both `lanczos` by default.<br>
`resolution_mode` sets the mode for layers without one, modes only matter for boxes and aspects.<br>
Sizes are rounded to even numbers for encoders that need it, `av1` and `nv_h264` keep odd sizes, the chain runs before the effects.

| Chain               | 1920x1080 source                                                                  |
|---------------------|-----------------------------------------------------------------------------------|
| `0.5x`              | 960x540.                                                                          |
| `720p`              | 1280x720.                                                                         |
| `5:4 crop 0.5x`     | Cuts the side bars off a stretched 5:4 game, then halves it to 675x540 with av1.  |
| `1080x1920 cover`   | Vertical 1080x1920, cutting the sides off.                                        |
| `1080x1920`         | Vertical 1080x1920, the whole frame with bars above and below.                    |
| `4:3 stretch`       | 1440x1080, squeezed.                                                              |
| `200% neighbor`     | 3840x2160, keeping hard pixel edges.                                              |

Recorders that stretch a lower game res over the whole screen, e.g. 1280x1024 recorded as 2560x1440, are undone with `1280x1024 stretch`, which gives back the native frame.<br>
Use `1024p` instead to keep it looking the way it did on screen.

### Effects

Tachytome offers a powerful effects and presets engine.<br>
These are extremely useful for adding transitions such as video/audio fade and blur.

Effects are defined in `.eff` files in `mpv/script-opts/tachytome/`, `default.eff` gets generated when there are none.<br>
You can find an example config with every option explained [here](./tachytome-effects.conf).

- Every `.eff` file in the dir is read in alphabetical order and shown as its own section in the Effects list:
  ```
  default
    fade
    blur_fade
  nnra6864
    dissolve
  ```
- Names only need to be unique within a file, different files can each have their own `fade`.
- `effects_presets` picks a preset from a specific file with `file/name`, e.g. `nnra6864/dissolve`, a bare name picks the first file that defines it.

```
effect blur_fade
    label Blur Fade
    duration 0.5
    param blur 200
    param curve ease_out_expo

    anchor start
    ramp {blur} 0 0 {curve}
    fade {curve}

    anchor end
    ramp 0 {blur} 0 {curve}
    fade {curve}
end
```

- `anchor` picks whether the following lines apply to the start or the end of the clip.
- `duration` and `param` values can be changed from the menu, and are used in the effect as `{name}`.
- `fade`, `vfade`, `afade`, `ramp`, `blur`, `tmix`, `vanimate` and `aanimate` cover the common cases.
- `video` and `audio` accept raw ffmpeg filters for everything else.
- Easings follow [easings.net](https://easings.net) in snake_case, custom curves can be made with `bezier(x1, y1, x2, y2)`.

### Path

Tachytome offers powerful path resolution.<br>
Config includes the `output_dir` option which you can set to the path you most commonly use, by default `~/Videos/tachytome`.

#### Prefixes

| Prefix | Resolves To                                    |
|--------|------------------------------------------------|
|        | Relative to the configured output_dir.         |
| ~      | Home on Unix, user directory on Windows.       |
| /      | Root directory.                                |
| ./     | Directory where the source file is.            |
| ../    | Parent directory of the configured output_dir. |

#### Examples

| Input      | Resolves To                    |
|------------|--------------------------------|
| CutClip    | ~/Videos/tachytome/CutClip.mkv |
| ~/CutClip  | ~/CutClip.mkv                  |
| /CutClip   | /CutClip.mkv                   |
| ./CutClip  | /path-to-source/CutClip.mkv    |
| ../CutClip | ~/Videos/CutClip.mkv           |

#### Display

To keep the menu narrow, paths are shown in their shortest form:
- under the source file's directory as `./Repo/Funny/MyClip.mkv`
- under the home directory as `~/Videos/tachytome/MyClip.mkv` (`~\Videos\...` on Windows)
- whichever of the two is shorter when both apply, otherwise the full path

While typing a path, the fully expanded path is shown below the input and updates as you type.<br>
This only affects what is displayed, ffmpeg and the render queue always use the full path.


## Contributing

If you are interested in contributing, feel free to just open a PR.<br>
The only thing I ask you to do is follow the [commit naming convention](https://www.conventionalcommits.org/en/v1.0.0/).<br>
AI is allowed as long as you fully review, understand and, most importantly, test the code.

Releases bump the version in [`src/version.lua`](./src/version.lua).<br>
A release that breaks old configs or files adds a handler to [`src/migrations`](./src/migrations), named after the version, e.g. `3_0_0.lua`, and listed in [`src/migrate.lua`](./src/migrate.lua).<br>
A handler has `detect` for installs without a version file, `prepare` for silent moves on start, and `plan`, `apply` and `skip` for changes the user decides on.<br>
Keep a copy of the previous version's builtin files in `src/migrations/<version>/` when the handler needs to tell user changes from defaults.

## Donations

Whilst Tachytome is entirely free, both as in speech and beer, I do highly appreciate donations as they are my only source of income.
- [Liberapay](https://liberapay.com/nnra6864/)
- [Ko-fi](https://ko-fi.com/nnra6864)

## AI

AI was heavily used in the making of Tachytome.<br>
As I am not yet familiar with Greek, I asked AI for Greek Eastern Orthodox words that would fit my app, and then combined the 2 suggestions.<br>
On top of that, AI wrote most of the code for me as I genuinely don't enjoy [Lua](https://www.lua.org/).<br>
To be precise:
1. I gave it my original [fish](https://fishshell.com/) script, [spc](https://git.nnstdios.com/nnra6864/Ricerland/src/branch/nous/.config/fish/functions/spc.fish).
2. Wrote instructions in pseudocode style that it translated to Lua.
3. Dictated the exact structure of the code.

In short, whilst AI did write the code itself, the logic/structure, README and the original idea came from me, not the AI.<br>
If that doesn't sit well with you, this repo is [CC0](https://creativecommons.org/publicdomain/zero/1.0/) licensed, so feel free to do whatever you want with the code and the idea, it's a gift.

# ☦

```
   Ὤ
 Ὁ   Ν
Ι̅Ϲ̅ │ Χ̅Ϲ̅
───┼───
ΝΙ │ ΚΑ
   ☦
```

Εἰς δόξαν τοῦ Θεοῦ<br>
*To the glory of God*

Τῇ Ὑπεραγίᾳ Θεοτόκῳ δόξα<br>
*Glory to the Most Holy Theotokos*

Δόξα τῷ Θεῷ πάντων ἕνεκεν<br>
*Glory to God for all things*

ΑΜΗΝ

☦
