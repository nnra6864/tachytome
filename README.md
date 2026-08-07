# Tachytome

Tachos (τάχος) – Speed<br>
Tome &nbsp;&nbsp;(τομή) &nbsp;– Cut

Keyboard Driven, AV1/Lossless, MPV Video Cutter.

## Installation

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
> For example, if your dotfiles are hosted on `https://git.nnstdios.com/name/dotfiles`, double `../` will make it go up twice in the URL, ending up with `https://git.nnstdios.com/`, and then appending `nnra6864/tachytome` to that, resulting in `https://git.nnstdios.com/nnra6864/tachytome`

### Clone

Alternatively, you may clone the repo directly to your config:

- Unix
```sh
git clone https://git.nnstdios.com/nnra6864/tachytome ~/.config/mpv/scripts/tachytome
```

- Windows (Powershell)
```sh
git clone https://git.nnstdios.com/nnra6864/tachytome "$env:APPDATA/mpv/scripts/tachytome"
```

## Usage

Tachytome is entirely keyboard driven.
All its binds are isolated into a submap (Tachytome Dashboard) to avoid global bind conflicts.
Here's a full list of binds:

| Keybind  | Action               | Description                                                                                       |
|----------|----------------------|---------------------------------------------------------------------------------------------------|
| Ctrl + t | Tachytome Dashboard  | Opens the Tachytome dashboard.                                                                    |
| i        | Mark In              | Marks the start of the video.                                                                     |
| o        | Mark Out             | Marks the end of the video.                                                                       |
| a        | Toggle Accurate Cut  | Makes cuts millisecond precise, but may cause a slight delay before rendering starts.             |
| l        | Toggle Lossless Cut  | Toggles the lossless cut option.                                                                  |
| c        | Toggle Combine Audio | Toggles the combine audio option.                                                                 |
| t        | Toggle Trash Source  | Trashes the source video when done.                                                               |
| q        | Set CRF              | Quality of the video ranging from 0-63.<br>&nbsp;0 - highest.<br>63 - lowest.                     |
| p        | Set Path             | Output path.<br>`~/` - home.<br>`./` - source dir.<br>No prefix - config `output_dir`.            |
| r        | Manage Render Queue  | Opens the render queue management dashboard where you can cancel active or remove queued renders. |
| Del      | Trash Source Now     | Trashes the source file.                                                                          |
| Enter    | Start Render         | Starts the rendering of the output file.                                                          |
| s        | Show Stats           | Displays Tachytome stats.                                                                         |
| Esc      | Close Menu           | Closes the currently active menu.                                                                 |

## Config

You can configure Tachytome with the `mpv/script-opts/tachytome.conf` file.<br>
It should get automatically generated on the first launch.<br>
You can find that same example config [here](./tachytome.conf).

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
