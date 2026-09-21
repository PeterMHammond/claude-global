---
name: kcc-forge
description: Drive the Kootenai Church sermon-forge pipeline — on-demand local whisper.cpp transcription of the KCC video corpus and phrase-based clip extraction for building shorts. Use whenever the user wants to START / PAUSE / RESUME / STATUS the transcription run, or asks to FIND or CLIP moments in the sermons ("every time Jim mentions Clark Fork", "pull clips where he talks about X", "give me the timestamps for Y"). On-demand only — nothing runs persistently; you explicitly start and stop it.
---

# KCC Sermon Forge

Local pipeline that transcribes the entire KCC YouTube corpus (2191 videos) with
whisper.cpp on the GPU and lets you search it to cut shorts. **Everything lives on
the T9 SSD; nothing auto-starts** (no cron, no systemd) — it is a job you turn on
and off.

- Forge root: `/mnt/Videos/KCC/forge`
- Tool: `/mnt/Videos/KCC/forge/bin/kcc` (Zig). While a transcription run is active,
  the binary is busy executing, so use `bin/kcc.new` for queries; promote it
  (`mv -f bin/kcc.new bin/kcc`) once the run is paused/finished.

## Turn it ON / OFF (transcription)

```bash
cd /mnt/Videos/KCC/forge
./bin/kcc status                                   # progress: N / 2191
# START or RESUME (GPU job):
./bin/kcc resume && nohup ./bin/kcc transcribe --workers 4 >> logs/transcribe.log 2>&1 &
# PAUSE (frees the GPU — do this before gaming):
./bin/kcc pause                                    # workers finish current video, then stop
```

Safe & resumable: a video is done when `whisper/<id>.json` exists; whisper writes a
`.tmp` then atomic-renames, so an interrupt just re-runs that one video. Optional
download-ahead accelerator: `nohup ./scripts/prefetch_audio.sh >> logs/prefetch.log 2>&1 &`
(network-bound — fine to run while the GPU is paused for a game).

## Find moments / cut clips (building shorts)

```bash
cd /mnt/Videos/KCC/forge
./bin/kcc search clark fork              # every mention -> title, timestamp, youtube deep-link
./bin/kcc search clark fork --json       # machine-readable array for the agent to relay

./bin/kcc clip clark fork --pre 20 --post 20
```
`clip` makes a folder per query and cuts **one clip per mention** (with `--pre`/`--post`
seconds of context before/after) from the local source video:

```
clips/clark-fork/
├── 20190310_WS_00-12-30_<id>.mp4   ← YYYYMMDD_WS|SS leads => sorts by timeline
├── 20211107_SS_00-41-05_<id>.mp4
└── manifest.json                    ← {video_id,title,url,clip_path,in_s,out_s,context_text,deeplink}
```
If a video has no local source, the mention still appears in the manifest with a
YouTube deep-link (`...&t=<sec>s`) so it can be pulled. Search/clip use whisper
transcripts where available, falling back to the YouTube-caption transcripts.

## Notes
- Source coverage grows as the run progresses; until a video is whisper'd, search
  uses its YouTube caption transcript.
- Migration of media to T9 + DaVinci Resolve relink: see `forge/scripts/migrate_to_t9.sh`
  (dry-run default; `--execute` to run) and `forge/scripts/RESOLVE_RELINK.md`.
- Quality check vs YouTube captions: `python3 forge/scripts/compare_whisper_youtube.py`.
