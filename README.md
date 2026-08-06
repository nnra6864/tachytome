# Tachytome

Tachos (τάχος) – Speed<br>
Tome   (τομή)  – Cut

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

### Clone

Alternatively, you may clone the repo directly to your config:

- Unix
```sh
git clone ../../nnra6864/tachytome ~/.config/mpv/scripts/tachytome
```

- Windows (Powershell)
```sh
git clone ../../nnra6864/tachytome "$env:APPDATA/mpv/scripts/tachytome"
```

## Usage

Tachytome is entirely keyboard driven, so here's a list of all the binds:

| Keybind          | Action               | Description                                                                                 |
|------------------|----------------------|---------------------------------------------------------------------------------------------|
| Ctrl + I         | Mark in              | Start of the video.                                                                         |
| Ctrl + O         | Mark out             | End of the video.                                                                           |
| Ctrl + Q         | Set CRF              | Quality of the video ranging from 0-63.<br>&nbsp;0 - highest.<br>63 - lowest.               |
| Ctrl + N         | Set path             | Output path.<br>&nbsp;`~` - home.<br>`./` - source dir.<br>No prefix - config `output_dir`. |
| Ctrl + T         | Toggle trash         | Trash the source video when done.                                                           |
| Ctrl + L         | Toggle lossless cut  | Toggles the lossles cut option.                                                             |
| Ctrl + A         | Toggle combine audio | Toggles the combine audio option.                                                           |
| Ctrl + S         | Stats                | Displays Tachytome stats.                                                                   |
| Ctrl + Del       | Trash                | Trashes the source file.                                                                    |
| Ctrl + Enter     | Render               | Renders the output file.                                                                    |
| Ctrl + Shift + S | Cancel render        | Cancels the current render.                                                                 |

## Config

You can configure Tachytome with the `mpv/script-opts/tachytome.conf` file:

```ini, toml
# Directory where all the renders will end up by default
# Set to empty for relative to source
# Also used as the starting point for the relative path
# Examples:
# `Repo/Funny/`   -> `~/Videos/Clips/Repo/Funny/MyClip.mkv`
# `./Repo/Funny/` -> `SourcePath/Repo/Funny/MyClip.mkv`
output_dir=~/Videos/Clips

# [C]onstant [R]ate [F]actor controls the visual quality of the output
# It ranges from 0-63, 0 being close to lossless, 63 being low quality
# Value of 30 is a great balance between quality and file size
# Can be dynamically set
crf=30

# Preset represents the effort of compression
# It ranges from 0-13, 0 being highest, 13 being lowest
# 4 is a great balance between speed and file size
preset=4

# Accurate cut results in millisecond perfect cuts, and is highly recommended
# Disabling this results in a fallback to keyframes
# The only downside is render taking longer to start if mark in is far in the video
# This shouldn't be a concern/issue in regular clips, but matters if you are cutting a movie
# Can be dynamically set
accurate_cut=yes

# Switches from the efficient AV1 compression to the lossless cut
# This means that the original encoder, data, etc. are fully preserved
# It results in instant render times, but often significantly larger file sizes
# Can be dynamically set
lossless_cut=no

# Combines all the existing audio tracks into a new one by default
# Useful if you split Desktop and Microphone audio into 2 tracks
# Can be dynamically set
combine_audio=no

# Name of the combined audio track
combined_audio_name=Combined

# Using spaces in names is highly discouraged for ease of use in CLI
# Therefore, Tachytome supports replacing spaces with a different character
# Set to ` `(space) to preserve spaces
# Set to ``(nothing) to remove spaces
space_replacement=_

# Suffix added to the default output name to avoid conflicts
# Set to ``(empty) if rendering to a dir different from where your source footage is
suffix= Remuxed

# Default suffix added to the output name when there's a naming conflict
conflict_suffix= Remuxed

# Container used for the output
# MKV is arguably the best in terms of features
container=mkv

# Will trash the source file when done rendering
# Can be dynamically set
trash_original=yes

# Will show the stats screen when done rendering
show_stats_screen=yes

# Duration for which UI will be shown
stats_osd_time=8
```

## Donations

Whilst Tachytome is entirely free, both as in freedom and beer, I do highly appreciate donations as they are my only source of income.
- [Librepay](https://liberapay.com/nnra6864/)
- [Ko-fi](https://ko-fi.com/nnra6864)

## AI

AI was heavily used in making of Tachytome.<br>
As I am not yet familiar with Greek, I asked AI for Greek Eastern Orthodox words that would fit my app, and then combined the 2 suggestions.<br>
On top of that, AI wrote most of the code for me as I genuinely don't enjoy [Lua](https://www.lua.org/).<br>
To be precise:
1. I gave it my original [fish](https://fishshell.com/) script, [spc](https://git.nnstdios.com/nnra6864/Ricerland/src/branch/nous/.config/fish/functions/spc.fish).
2. Wrote instructions in pseudo code style that it translated to lua.
3. Dictated the exact structure of the code.

In short, whilst AI did write the code itself, logic/structure, README and the original idea came from me, not the AI.<br>
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
