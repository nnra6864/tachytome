# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings go in every language file, `lang/en.lua` and `lang/sr.lua`.

## 1. Effect parameter names are translatable
- The names prompted when adding an effect, e.g. `curve` or `blur`, can
  get a display name per language, so `{curve}` keeps working inside the
  effect while the prompt shows a translated name.
- The effects that come with Tachytome get Serbian names for theirs.
- Not urgent.
