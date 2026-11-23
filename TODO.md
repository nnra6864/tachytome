# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings go in every language file, `lang/en.lua` and `lang/sr.lua`.

## 1. Confirmation dialogs show what they change
- Where a dialog decides something you can't see from the dialog itself,
  it lists what changes, short and dim under the question, e.g.:
  - Unsaved changes in the Config Editor: each changed option as
    `quality 35 -> 40`, an unset one as `quality 40 -> unset`.
  - Reset in the Preset Manager: the presets in each file that goes, and
    the builtins that go back on or off.
  - Reset in the Config Manager: the options in `user.conf` and the
    configs that get deleted.
  - Deleting a config: the options it sets.
- Long lists are cut to a few lines with `and N more`, the same way the
  migration lists are.
- Dialogs whose question already says it all, like Yes/No to enable a
  config or Rename/Overwrite for a render, stay as they are.

## 2. Effect parameter names are translatable
- The names prompted when adding an effect, e.g. `curve` or `blur`, can
  get a display name per language, so `{curve}` keeps working inside the
  effect while the prompt shows a translated name.
- The effects that come with Tachytome get Serbian names for theirs.
- Not urgent.
