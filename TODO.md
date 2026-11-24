# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings go in every language file, `lang/en.lua` and `lang/sr.lua`.

## 1. Edit renders in the Render Queue
- A key in the Render Queue, e.g. `e`, opens the whole Tachytome menu for
  the selected queued or failed render: marks, quality, encoder, effects,
  tracks, path and everything else.
- Confirming puts the edited render back in the queue, failed ones
  included, going through the same losses dialog as a new render.
- The Render Queue also shows each render's progress and an ETA, from the
  `speed=` and `out_time_us` ffmpeg's `-progress` already writes, renders
  can be reordered, and a render's settings can be viewed.
- Big step, not started.

## 2. Config warnings show when the menu opens
- Invalid lines, unknown actions or keys, shadowed sequences and redefined
  presets only go to the terminal now.
- Opening the Tachytome menu lists them all on the OSD, one per line,
  instead of popping up at startup.

## 3. Go To checks what's typed
- Invalid input keeps the prompt open with an error instead of closing it
  silently.
- Setting a mark so Mark In ends up after Mark Out warns right away
  instead of only at render time.
- Repeated dots, e.g. `5.........1`, are rejected or kept to one instead
  of reading as `5.1`.

## 4. Lists fit the screen
- Lists show as many rows as the OSD height and `font_size` allow instead
  of a fixed 15.

## 5. Loading current values in the Config Editor lists them
- `l` asks first with the changes it would load, `quality 35 -> 40` one
  per line like saving does, instead of only counting them.

## 6. Smaller performance fixes
- Autocrop runs at most 2-3 ffmpeg decoders at once, waits for marks to
  settle and forgets old results per file.
- The Config Editor parses the builtin config once instead of on every
  draw.
- The ffprobes at render start, creation time and stream info, run in the
  background.

## 7. URL and ytdl sources [?]
- ffmpeg reads plain http(s) media URLs directly, so those mostly need the
  output name taken from `media-title`, no Trash Source, and no size from
  `file_info`.
- ytdl sources aren't trivial: mpv plays the page URL through
  `stream-open-filename`, often an `edl://` joining separate video and audio
  streams with their own headers, which ffmpeg can't read, and the stream
  URLs expire.
- Open question: read the streams mpv resolved, one `-i` per stream with
  their headers, or hand the cut to `yt-dlp --download-sections` and render
  from that.

## 8. Restructure, once the features above are in
- Audit section 4: one job record, data-driven encoders, a view helper for
  every OSD screen, a preset store factory, one file module with atomic
  writes, `common.lua` split up, one owner for state, tests for the pure
  logic and `ffmpeg.build_args` snapshots.
