# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

Track chain strings are English only until the feature is final, no `sr`.

## 1. Tracks menu
- Layout like the Resolution List: Presets row, Layers, then Output.
- Layers: Enter edits, `a` adds after the selected one, `d` deletes,
  Shift+Up/Down/`J`/`K` move, `p` opens Presets.
- Output lists the resulting tracks live in their final order, each with
  its title, codec, channels, language and where it comes from, e.g.
  `source 1` or `mix 1+3+5`; the title shows `5 in > 4 out`.
- 0-9/Enter on an Output row drops or restores it through one trailing
  `drop` layer, created when needed and removed once empty; it sits before
  the trailing `mix`/`only` that Combine Audio and Combined Only manage.
- Editing a layer's list opens a source picker of the tracks present at
  that layer, `A` switches Include (stored as `1,3`) and All except
  (everything starts on, stored as `-2,5`), the heading shows the mode.
- Mix layers also edit their name and position.
- `v` shows the video tracks as a plain toggle list, `a` goes back.

## 2. Track presets
- `~~/script-opts/tachytome/*.trk` files, `name = chain`, read like the
  `.res` files, `file/name` picks one from a specific file, presets work
  as tokens in the chain.
- Presets can hold audio layers and video tokens together.
- Presets list from the Presets row and `p`, numbered and searchable,
  0-9/Enter replaces the chain, `a` adds it after the selected layer.
- The generated `default.trk` holds `combined = mix` and
  `combined_only = mix only`.
