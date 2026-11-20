# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

Resolution strings are English only until the feature is final, no `sr`.

## 1. Resolution presets
- `~~/script-opts/tachytome/*.res` files, one preset per line,
  `name label tokens...`, read like the `.eff` files, `file/name` picks
  one from a specific file.
- Preset names are tokens in the chain and expand inline, so one preset
  can hold several layers, e.g. `cs = 1280x1024 stretch`, used as
  `cs 0.5x`.
- The generated default file holds the named sizes: `720p`-style names,
  `hd`, `fhd`, `qhd`, `uhd`, `2k`, `4k`, `8k`.
- Resolution List inputs: Down past the newest history entry walks the
  presets, so `a` and Enter can pick one.

## 2. Auto crop
- `auto` token: crops black bars found by ffmpeg's `cropdetect`, look up
  its current options first.
- Samples spread over the cut range, never only its start, the largest
  box over all samples wins so dark scenes can't over-crop.
- Runs async as soon as the token is added, the row shows
  `auto -> 1350x1080` or `no bars`, cached per file and cut range, the
  render waits for a pending detection.
- README: the gsr/stretched case is `1280x1024 stretch`, not `auto`.
