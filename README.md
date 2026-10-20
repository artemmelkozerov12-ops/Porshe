# DRIPWORKER — Porsche 911 Turbo S

Cinematic 2.5D motion piece built from a single photo. The car is never redrawn or
deformed: every frame is the original photo, moved by a virtual camera and lit with
overlays (light sweeps, anamorphic flares, grade, grain, typography).

## Output

| File | Format |
|---|---|
| `output/dripworker_911_turbo_s_4x5.mp4` | 1080×1350, 24 fps, 34 s — Instagram / Behance |
| `output/dripworker_911_turbo_s_9x16.mp4` | 1080×1920, 24 fps, 34 s — Reels / Shorts / TikTok |
| `output/stills/` | poster and case-study frames |
| `output/audio/track.wav` | original soundtrack, 48 kHz stereo |

## Structure (120 BPM, cuts on the beat)

| Time | Shot |
|---|---|
| 0–4 s | Intro: author title, accelerating flash cuts, pre-drop gap |
| 4–8 s | Drop: reveal, "911 TURBO S" title |
| 8–20 s | Details: 01 Face · 02 Stance · 03 Crest · 04 Aero (whip transitions) |
| 20–28 s | Specification with count-up numbers |
| 28–34 s | Outro: headlight flares, DRIPWORKER end card |

## Build

```bash
python3 src/music.py      # synthesizes output/audio/track.wav + src/beats.json
python3 src/prep.py       # 2x upscale of src/car.jpg
export NODE_PATH=/opt/node22/lib/node_modules   # global playwright
node src/render.cjs video 1080 1350 output/dripworker_911_turbo_s_4x5.mp4
node src/render.cjs video 1080 1920 output/dripworker_911_turbo_s_9x16.mp4
node src/render.cjs stills 1080 1350 output/stills 5.8 13.6 26 31.8
```

Texts, model name and specs live in `src/config.json`. The scene itself is
`src/scene.html` (canvas, deterministic `seek(t)`); `render.cjs` drives it frame by
frame with Playwright and pipes PNGs into ffmpeg.

Specs are official Porsche figures for the 992.1 911 Turbo S. If the car is a
Turbo (non-S), switch to 580 PS · 750 Nm · 2.8 s · 320 km/h.

Photo: author unknown — add the photographer's credit in `config.json` → `credit`.
