# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

Track chain strings are English only until the feature is final, no `sr`.

## 1. Track chain and syntax
- Audio is a chain of layers applied in order, written as one line, e.g.
  `mix -2 "Voice" at 2 drop 3,5`, each op word starts a new layer like
  size tokens do in Resolution, each layer works on the track list the
  layers before it left.
- Sources are referred to by their original numbers, mixes by name, so
  inserting a mix never renumbers anything typed; mix names are unique.
- Source lists: `1,3`, `all`, `none`, `all -2,5`, `-2,5` (a leading `-`
  implies `all`), names work in them too, e.g. `Voice,4` or `-Voice`.
- `all` means every track present at that layer, earlier mixes included,
  so `mix; mix all` mixes the sources and the first mix again.
- Layers:
  - `keep <list>`: keep only these.
  - `drop <list>`: remove these.
  - `mix [list] ["name"] [at N]`: new track from the list, all kept
    tracks when omitted, `at N` is its output position, the end when
    omitted; unnamed mixes are `Mixed`, `Mixed 2`, ...
  - `only`: keep just the mixes.
- Video keeps a plain set, written as `video 1`, `video none`, ... in the
  same chain, shown and edited separately from the audio layers.
- ffmpeg: one graph for any number of mixes, `asplit` each track by how
  many times it's used, mixes of mixes chained, audio effects per output
  track like now, the first mix is the default track.
- Container picking, single track formats and the audio only default name
  follow the chain's output instead of `combine_audio`.
- Config: `tracks` replaces `audio_tracks`, `video_tracks`,
  `combine_audio`, `combined_audio_only` and `combined_audio_name`; the
  queue and recovery store the chain.
- Migration turns the old options into a chain, the name moving into the
  mix; the Combine Audio and Combined Only menu entries go away.
- Errors name the bad token, e.g. an unknown name or a missing track.

## 2. Tracks menu
- Layout like the Resolution List: Presets row, Layers, then Output.
- Layers: Enter edits, `a` adds after the selected one, `d` deletes,
  Shift+Up/Down/`J`/`K` move, `p` opens Presets.
- Output lists the resulting tracks live in their final order, each with
  its title, codec, channels, language and where it comes from, e.g.
  `source 1` or `mix 1+3+5`; the title shows `5 in > 4 out`.
- 0-9/Enter on an Output row drops or restores it through one trailing
  `drop` layer, created when needed and removed once empty.
- Editing a layer's list opens a source picker of the tracks present at
  that layer, `A` switches Include (stored as `1,3`) and All except
  (everything starts on, stored as `-2,5`), the heading shows the mode.
- Mix layers also edit their name and position.
- `v` shows the video tracks as a plain toggle list, `a` goes back.

## 3. Track presets
- `~~/script-opts/tachytome/*.trk` files, `name = chain`, read like the
  `.res` files, `file/name` picks one from a specific file, presets work
  as tokens in the chain.
- Presets can hold audio layers and video tokens together.
- Presets list from the Presets row and `p`, numbered and searchable,
  0-9/Enter replaces the chain, `a` adds it after the selected layer.
- The generated `default.trk` holds `combined = mix` and
  `combined_only = mix only`.
