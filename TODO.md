# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

Track chain strings are English only until the feature is final, no `sr`.

## 1. Track presets
- `~~/script-opts/tachytome/*.trk` files, `name = chain`, read like the
  `.res` files, `file/name` picks one from a specific file, presets work
  as tokens in the chain.
- Presets can hold audio layers and video tokens together.
- A Presets row in the Tracks list under Chain, showing the preset in use,
  and `p` from any row open the Presets list, numbered and searchable,
  each with its chain and the `in > out` it gives; 0-9/Enter replaces the
  chain, `a` adds it after the selected layer.
- The generated `default.trk` holds `combined = mix` and
  `combined_only = mix keep @mixes`.
