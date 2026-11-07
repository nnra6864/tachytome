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
  - [Dependencies](#dependencies)
  - [Clone](#clone)
  - [Submodule](#submodule)
- [Usage](#usage)
  - [Quickstart](#quickstart)
  - [Keymap](#keymap)
  - [Config](#config)
  - [Recovery](#recovery)
  - [Go To](#go-to)
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
- `r` to access the render queue.

### Keymap

| Keybind | Action | Description              |
|---------|--------|--------------------------|
| t       | Menu   | Open the Tachytome menu. |
| nil     | Go To  | Open the Go To menu.     |
| nil     | Trash  | Trash current file.      |

#### Menu

| Keybind | Action            | Description                                                                                                   |
|---------|-------------------|---------------------------------------------------------------------------------------------------------------|
| i       | Mark In           | Mark the start of the video.                                                                                  |
| o       | Mark Out          | Mark the end of the video.                                                                                    |
| g       | Go To             | Go to a precise location in the video.<br>Learn more about [Go To](#go-to).                                   |
| ctrl+i  | Set In            | Type in the Mark In, same input as [Go To](#go-to).                                                           |
| ctrl+o  | Set Out           | Type in the Mark Out, same input as [Go To](#go-to).                                                          |
| <hr>    | <hr>              | <hr>                                                                                                          |
| e       | Encoder           | Set the video encoder.                                                                                        |
| q       | Quality           | Set the video encoder quality parameter.                                                                      |
| P       | Preset            | Set the video encoder preset parameter.                                                                       |
| F       | FPS               | Set the FPS of the video.                                                                                     |
| k       | Keyframes         | Set the keyframe interval, e.g. `120` frames or `2s`.<br>Empty uses the encoder default.                      |
| l       | Lossless Cut      | Toggle the lossless cut option.                                                                               |
| a       | Accurate Cut      | Toggle accurate cut.<br>Makes cuts millisecond precise, but may cause a slight delay before rendering starts. |
| <hr>    | <hr>              | <hr>                                                                                                          |
| c       | Combine Audio     | Toggle the combine audio option.                                                                              |
| A       | First Audio Only  | Toggle the first audio only option.                                                                           |
| <hr>    | <hr>              | <hr>                                                                                                          |
| E       | Effects           | Select the effects applied to the output.<br>Learn more about [Effects](#effects).                            |
| <hr>    | <hr>              | <hr>                                                                                                          |
| _       | Space Replacement | Set the character to replace spaces with.                                                                     |
| p       | Path              | Set Output path.<br>Learn more about [Path](#path).                                                           |
| t       | Trash Source      | Toggle trashing of the source file on render completion.                                                      |
| <hr>    | <hr>              | <hr>                                                                                                          |
| Enter   | Render            | Start the render of the output file.                                                                          |
| r       | Render Queue      | Open the render queue menu.                                                                                   |
| R       | Pause Render      | Pause the current render and render queue.<br>Can only pause the render queue on Windows.                     |
| d       | Trash Source Now  | Trash the source file.                                                                                        |
| s       | Stats             | Toggle the Tachytome stats overlay.                                                                           |
| <hr>    | <hr>              | <hr>                                                                                                          |
| m       | Menu              | Switch the menu, saved to your config.<br>Learn more about [Custom Menus](#custom-menus).                     |
| c       | Configs           | Enable, disable and reorder extra configs.<br>Learn more about [Configs](#configs).                           |
| l       | Language          | Switch the UI language, saved to your config.<br>Learn more about [Translations](#translations).              |
| U       | Update            | Update Tachytome using git, falls back to the GitHub archive.<br>Restart mpv after updating.                  |
| Esc     | Close             | Close the currently active menu.                                                                              |

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

Inputs like the Path prompt use ctrl+k/ctrl+j instead, since plain letters are typed into the input.

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

> [!NOTE]
> Older versions used `mpv/script-opts/tachytome.conf` and `mpv/script-opts/tachytome-effects.conf`.<br>
> These get moved to `mpv/script-opts/tachytome/default.conf` and `mpv/script-opts/tachytome/default.eff` on start, with a new `tachytome.conf` sourcing `default`.<br>
> A `tachytome/tachytome.conf` without a `configs=` line is moved to `default.conf` the same way, and a `tachytome/effects.conf` to `default.eff`.

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
- Switching the menu or language from the menu saves it to whichever file sets it, e.g. `work.conf` when it's the one that wins.<br>
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
| empty line                | Separator.                                                                      |

Hidden items keep working from their keys.<br>
A hidden submenu, e.g. `hide s-s settings {`, still opens and shows its items, only its row is gone from the parent list.

Labels starting with `@` are [translation](#translations) keys, e.g. `@menu_set_mark_in Set In`, with the rest used as the fallback.<br>
Use `@@` for a label that starts with `@`.

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
- Submenus are labeled by `submenu_<id>`, e.g. `submenu_video`, or their id when there's no such key.
- Menu item labels, `menu_<action>`, are reused as the titles of the screens they open and in their notifications, e.g. `Quality: 30`.
- Key tooltips are built from `key_hint`, e.g. `{keys} to {action}`, and one `key_<action>` per action, e.g. `key_navigate`.
- To add a language, copy `lang/en.lua` to `lang/<code>.lua` and translate the text.

### Recovery

Tachytome gracefully handles crashes and accidental closes.<br>
Render queues are stored as files tied to the mpv PID.<br>
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
Config includes the `output_dir` option which you can set to the path you most commonly use, by default `~/Videos/Tachytome`.

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
| CutClip    | ~/Videos/Tachytome/CutClip.mkv |
| ~/CutClip  | ~/CutClip.mkv                  |
| /CutClip   | /CutClip.mkv                   |
| ./CutClip  | /path-to-source/CutClip.mkv    |
| ../CutClip | ~/Videos/CutClip.mkv           |

#### Display

To keep the menu narrow, paths are shown in their shortest form:
- under the source file's directory as `./Repo/Funny/MyClip.mkv`
- under the home directory as `~/Videos/Tachytome/MyClip.mkv` (`~\Videos\...` on Windows)
- whichever of the two is shorter when both apply, otherwise the full path

While typing a path, the fully expanded path is shown below the input and updates as you type.<br>
This only affects what is displayed, ffmpeg and the render queue always use the full path.


## Contributing

If you are interested in contributing, feel free to just open a PR.<br>
The only thing I ask you to do is follow the [commit naming convention](https://www.conventionalcommits.org/en/v1.0.0/).<br>
AI is allowed as long as you fully review, understand and, most importantly, test the code.

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
