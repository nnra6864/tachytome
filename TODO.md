# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

Resolution strings are English only until the feature is final, no `sr`.

## 1. Auto crop
- `auto` token: crops black bars found by ffmpeg's `cropdetect`, look up
  its current options first.
- Samples spread over the cut range, never only its start, the largest
  box over all samples wins so dark scenes can't over-crop.
- Runs async as soon as the token is added, the row shows
  `auto -> 1350x1080` or `no bars`, cached per file and cut range, the
  render waits for a pending detection.
- README: the gsr/stretched case is `1280x1024 stretch`, not `auto`.
