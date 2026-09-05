# Tachytome Agent TODO

Ordered task list. Work through **one item at a time**, then stop and wait for
review/commit before starting the next (see AGENTS.md). Items are ordered so
each one builds on the state left by the previous ones — don't reorder
without flagging why first.

## Global notes
- No external/third-party dependencies (LuaRocks packages, vendored libs,
  etc.) unless something is genuinely impossible without one. If you think
  you need one, stop and ask before adding it.
- Several items below depend on earlier ones (temp-file rendering underpins
  the rename fix, completion detection, and the persistent queue). Don't
  jump ahead in the list.
- Where a design decision isn't pinned down below, make a reasonable choice,
  but call it out explicitly when you report back — don't silently pick one
  and move on.

## 1. Render to a temp file, then rename on completion
Stop writing ffmpeg output directly to the target path. Render to a
temporary file first (e.g. `.tachytome_tmp_<id>.mkv`, one per queue item so
nothing collides), placed in the same directory as the intended final output
so the final move is a same-filesystem rename, not a cross-device copy.
- Only rename temp → final path once ffmpeg has actually exited with code 0
  (see item 3 for what "actually done" should mean).
- On failure or cancellation, delete the temp file.
- "Trash source" must only ever fire *after* the successful rename to the
  final path — never before.
- On startup, if a leftover temp file exists with no corresponding completed
  entry, treat it as an orphan from a crash and surface it rather than
  silently overwriting or ignoring it.

## 2. Rename support in the render queue (including the active render)
- Queued, not-yet-started items: renaming is just updating the stored
  output-path field.
- The currently rendering item: since output now goes to a temp file first
  (item 1), renaming the active render is just updating the recorded
  *final* target path — no interaction with the live ffmpeg process needed.
- Reuse the existing path-input validation logic (extension handling,
  space-replacement, directory checks) for the new name.
- Pick a free keybind in the render-queue submenu; check the existing bind
  table first to avoid clashing.

## 3. Fix render progress falsely showing 100%
Figure out the actual root cause — likely candidates: percentage computed
from an estimated duration that doesn't exactly match the real encode
length, or a stderr/progress line arriving before the muxer has actually
finished writing.
- The single source of truth for "render is done" must be the process
  actually exiting (exit code 0), never the displayed percentage reaching
  100.
- If not already using it, consider `-progress pipe:1` for cleaner parsing
  (`progress=end` as the completion signal).
- The displayed percentage can stay an approximation — it just must never
  read 100% while the process is still running.

## 4. Correct in/out time display for lossless cut
Lossless cut is a stream copy, so the actual cut points snap to the nearest
keyframe — they are not the exact timestamps the user marked in/out at.
Right now the displayed time is the raw marked timestamp even when that
isn't what will actually get cut.
- When lossless is active, resolve the real cut points via one `ffprobe`
  pass per mark (nearest keyframe at/before the in-point; equivalent logic
  for out) and display the resolved time, or both requested and resolved
  time if they differ.
- This must **live-update**: toggling lossless on/off, or toggling accurate
  cut, must immediately recompute and refresh the displayed in/out time —
  the user shouldn't need to re-mark in/out for the display to become
  correct.
- When accurate cut is active, the raw marked time is already correct —
  don't run it through keyframe resolution.
- Cache the keyframe lookup per source file so you're not re-probing on
  every toggle; invalidate the cache if the source file changes.
- Read the current in/out-marking and lossless/accurate-cut toggle code
  first to confirm exactly how the two options currently interact before
  touching display logic.

## 5. Shift+I / Shift+O — go to marked in/out
Add binds in the Tachytome Menu submap: Shift+I seeks playback to the stored
"in" timestamp, Shift+O seeks to the stored "out" timestamp. Show an OSD
message (don't fail silently) if the relevant mark hasn't been set yet.

## 6. Customizable ASS text shadow
Add shadow color and shadow depth/width to `tachytome.conf`, following the
same customization pattern already used for other visual config (colors,
outline, etc.).
- This is a plain ASS shadow: `\shad` for depth, `\3c`/`\4c`-style tags for
  color — a single uniform offset, not independent x/y. That's a real
  limitation of ASS, not a bug to work around; don't try to fake directional
  shadow here.
- If the default-config generator has existing inline comments explaining
  each option, match that style for the new ones. Don't write any prose
  documentation or README content — see AGENTS.md.

## 7. Ctrl+j/k vim-style navigation (yazi-style)
Field history (for input fields) and list navigation already exist and are
already reachable via the arrow keys. This item is purely additive: bind
Ctrl+j / Ctrl+k to trigger the exact same behavior the arrow keys already
do. Vertical only — no h/l needed.
- Ctrl+j / Ctrl+k on an input field: same history-step behavior as the
  existing up/down-arrow handling.
- Ctrl+j / Ctrl+k on a selection list: same up/down selection-move behavior
  as the existing arrow-key handling.
- Holding Ctrl is what avoids clashing with other existing binds. Don't
  change or replace the existing arrow-key behavior — just wire Ctrl+j/k to
  call the same handlers.

## 8. Pause/resume rendering (Shift+P)
- **Linux, and macOS if it behaves the same** (not actively supported or
  tested by the user, but fine to enable if it just works): pause by
  sending `SIGSTOP` to the live ffmpeg process, resume with `SIGCONT`. This
  is a true suspend — zero CPU while paused, resumes exactly where it left
  off, no re-encoding needed.
- **Windows has no equivalent.** Do not attempt to fake process suspension
  on Windows (no pssuspend / `NtSuspendProcess`-style native calls — that's
  an external dependency the user explicitly doesn't want). Instead, on
  Windows, Shift+P should pause the *queue*: let the currently rendering
  file finish normally, then don't start the next queued item until
  resumed. Make the OSD wording reflect the difference clearly (immediate
  pause on Linux/Mac vs. "finishing current file, then pausing" on
  Windows).
- **Blocking prerequisite — flagging this explicitly:** sending signals
  requires the real OS PID of the ffmpeg child process. Before building
  this, check whether the current subprocess launch method actually exposes
  a live PID for a running async subprocess. If it's mpv's built-in
  `subprocess` command, note that this is primarily designed for
  *aborting* an in-flight command, not suspending one — confirm current
  behavior against up-to-date docs rather than assuming (see AGENTS.md on
  not guessing APIs). If a live PID isn't available this way, you'll need a
  small wrapper (e.g. a shell layer that captures `$!` and writes it
  somewhere tachytome can read back) — work this out and report back before
  building the rest of the feature on top of it.
- Also worth confirming and reporting: if mpv itself crashes or closes
  while a render is `SIGSTOP`-paused, does the ffmpeg process survive
  (detached) or die with it? This affects what item 9's crash-recovery
  logic actually needs to handle.

## 9. Persistent render queue file
Once pause/resume exists, switch the render queue to be backed by a file so
it survives an mpv crash or restart.
- No external dependencies — no pulling in a JSON library. Use a simple
  hand-rolled serialization (whatever's simplest to write/parse reliably in
  Lua — e.g. a minimal custom format, or a `return { ... }` Lua table
  loaded back with `load`/`loadstring`). Your call, just keep it
  dependency-free and resilient to a partially-written file.
- Store everything currently tracked per queue item: input path, final
  output path, in-progress temp filename, in/out times (raw +
  lossless-resolved, per item 4), encoder, quality, preset, all toggles
  (lossless, accurate cut, combine audio, trash source), space-replacement
  char, and status (queued/active/paused/done/failed).
- Write atomically: write to a temp file, then rename over the real queue
  file, so a crash mid-write can't corrupt the recovery state.
- On mpv startup, read this file. Any item not marked "done" should be
  offered for resume or discard from the render queue menu, as originally
  intended.

## 10. Pause indicator in the Tachytome menu
When a pause is active (either an immediate `SIGSTOP` pause or a
"finishing current file, then pausing" queue-level pause on Windows), show a
clear indicator in the same area where render progress normally displays,
whenever the Tachytome Menu is open. Distinguish the two pause states in the
text if that's not awkward to do.
