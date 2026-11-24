# TODO

Items are ordered for implementation, one at a time. `[?]` marks an open
question that needs an answer before that item starts.

New strings go in every language file, `lang/en.lua` and `lang/sr.lua`.

## Before bumping the version
- `stats.json` went to `"version": 2`, with the old totals kept in a
  `legacy` block and in `stats.v1.json`. Check that naming still fits the
  release it ships in.

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

## 3. Loading current values in the Config Editor lists them
- `l` asks first with the changes it would load, `quality 35 -> 40` one
  per line like saving does, instead of only counting them.

## 4. Smaller performance fixes
- Autocrop runs at most 2-3 ffmpeg decoders at once, waits for marks to
  settle and forgets old results per file.
- The ffprobes at render start, creation time and stream info, run in the
  background.

## 5. URL and ytdl sources [?]
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

## 6. Restructure, once the features above are in
- Audit section 4: one job record, data-driven encoders, a view helper for
  every OSD screen, a preset store factory, one file module with atomic
  writes, `common.lua` split up, one owner for state, tests for the pure
  logic and `ffmpeg.build_args` snapshots.
