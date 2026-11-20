# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

Resolution strings are English only until the feature is final, no `sr`.

## 1. Resolution chain and syntax
- A chain of layers applied in order, written as one line, e.g.
  `5:4 crop 0.5x lanczos`.
- Size tokens start a new layer:
  - `0.5x`, `50%`: multiplier, keeps the aspect.
  - `1920x1080`: a box.
  - `1280x`, `x720`, `720p`: one side, keeps the aspect.
  - `4:3`: aspect, keeps the res; the largest box of that aspect inside
    the frame for `cover` and `crop`, the smallest one around it for
    `fit`, the height is kept for `stretch`.
- Mode and scaler words apply to the layer before them, omitted ones use
  the defaults; a mode on a multiplier is ignored.
- Modes: `fit` (default, scale inside and pad), `cover` (scale over and
  crop the center), `stretch` (ignore the aspect), `crop` (no scaling,
  cut the center).
- Scalers: every ffmpeg scaler, including `neighbor`; each layer picks
  `scaler_down` or `scaler_up` by whether it shrinks or grows. Look up
  the current swscale flags and pick the defaults from that.
- Config: `resolution` (default chain, empty keeps the source),
  `resolution_mode`, `scaler_down`, `scaler_up`, `pad_color`.
- Pipeline: after `fps=` and before the effects, sizes rounded to even,
  `setsar=1` at the end, any layer turns lossless cut off like effects do.
- Errors name the bad token, e.g. a `crop` bigger than the frame.

## 2. Resolution menu
- Video -> Resolution on `r`.
- Quick row on top: one input that replaces the whole chain, Up walks the
  history, Down past the newest entry walks the presets.
- One row per layer showing size, mode, scaler and `in -> out` sizes,
  the title shows the whole `source -> ... -> output` path from
  `video-params`; the input shows the output size live while typing.
- Enter edits the layer's size, `m` cycles the mode, `s` the scaler, `d`
  deletes, `J`/`K` move, `a` adds a layer from text or a preset.

## 3. Resolution presets
- `~~/script-opts/tachytome/*.res` files, one preset per line,
  `name label tokens...`, read like the `.eff` files, `file/name` picks
  one from a specific file.
- Preset names are tokens in the chain and expand inline, so one preset
  can hold several layers, e.g. `cs = 1280x1024 stretch`, used as
  `cs 0.5x`.
- The generated default file holds the named sizes: `720p`-style names,
  `hd`, `fhd`, `qhd`, `uhd`, `2k`, `4k`, `8k`.

## 4. Auto crop
- `auto` token: crops black bars found by ffmpeg's `cropdetect`, look up
  its current options first.
- Samples spread over the cut range, never only its start, the largest
  box over all samples wins so dark scenes can't over-crop.
- Runs async as soon as the token is added, the row shows
  `auto -> 1350x1080` or `no bars`, cached per file and cut range, the
  render waits for a pending detection.
- README: the gsr/stretched case is `1280x1024 stretch`, not `auto`.
