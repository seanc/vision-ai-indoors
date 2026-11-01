# Indoor Vision

A small, readable version of the bike-vision architecture that you can run at home.
Point a camera down a hallway and walk towards it: the server detects you, tracks
you across frames, works out which half of the "path" you're in, and decides
`CLEAR`, `CAUTION` or `YIELD`.

```
capture  ->  perception  ->  tracking  ->  path understanding  ->  decision
browser      YOLO (ONNX)     IoU tracker   hand-drawn lane         rules + hysteresis
```

The point is to prove the pipeline end to end (phone or webcam → Phoenix Channel →
Evision + Ortex → back to the screen) before any custom model training happens.

## What's different from the bike version

| Bike plan | Here |
|---|---|
| Path segmentation model, trained on my footage | A fixed trapezoid "lane" (`Zones`). Same output: `my_half` / `oncoming_half` / `off_path` |
| Phone on handlebars, outdoors | Laptop webcam or phone, in a hallway |
| Pedestrians, bikes, dogs on a trail | You (or a pet) walking towards the camera |

Everything else (the transport, the per-session process, YOLO, the tracker, the
decision rules) is the same design the bike version will use.

## Running it

```bash
mix setup                 # deps + assets
scripts/export_yolo.sh    # one-off: exports yolo11n to priv/models/yolo11n.onnx (needs uv)
mix phx.server
```

Open <http://localhost:4000>, press **Start camera**, and walk towards it.
**Use a video file** runs the same pipeline on a recorded clip.

### On your phone (Tailscale)

Phone browsers only allow camera access over HTTPS. Tailscale gives the Mac a
real certificate on your tailnet:

```bash
tailscale up              # if it's stopped
tailscale serve --bg 4000 # https://<this-mac>.<tailnet>.ts.net -> localhost:4000
```

Open the `https://….ts.net` address on the phone (Tailscale on). The first run
may ask you to enable HTTPS certificates in the Tailscale admin console.
`tailscale serve reset` stops it. No Phoenix changes are needed: dev already
has `check_origin: false`, so the WebSocket accepts the `.ts.net` origin.

No Tailscale? `cloudflared tunnel --url http://localhost:4000` gives a public
`trycloudflare.com` URL instead. It works, but frames take a detour through
Cloudflare, adding latency.

## Reading the code

Start with `Pipeline`, which calls each stage in order. Every module explains
itself at the top.

| Stage | File | What it does |
|---|---|---|
| Capture | `assets/js/vision/camera.js` | Webcam/video → JPEG |
| | `assets/js/vision/orientation.js` | Phone tilt, level indicator |
| | `assets/js/vision/connection.js` | Binary frame push over the channel |
| | `assets/js/vision/index.js` | The frame loop (one frame in flight at a time) |
| | `assets/js/vision/overlay.js` | Draws lane, guides, boxes |
| Transport | `lib/indoors_experiments_web/channels/vision_channel.ex` | One process per browser tab; holds the session's state |
| Perception | `lib/indoors_experiments/vision/detector.ex` | Loads the model, runs JPEG → detections |
| | `…/vision/preprocess.ex` | Decode, letterbox, → `{1,3,640,640}` |
| | `…/vision/yolo_decoder.ex` | `{1,84,8400}` → boxes (threshold, NMS, undo letterbox) |
| Tracking | `…/vision/tracker.ex` | Match boxes across frames, measure growth = approaching |
| Path | `…/vision/zones.ex` | Which half of the lane is an object standing in? |
| Decision | `…/vision/decision.ex` | Rules, then hysteresis so it doesn't flicker |
| Debugging | `…/vision/recorder.ex`, `annotate.ex`, `session_report.ex` | Session recordings and reports |

The numbers worth tuning (thresholds, lane shape, frames to switch) are module
attributes at the top of `tracker.ex`, `zones.ex`, `decision.ex` and
`yolo_decoder.ex`.

## Recordings and reports

Every session is saved to `tmp/sessions/<timestamp>/` (`tmp/sessions/latest`
points at the newest):

- `frames.jsonl`: every frame's metadata, tracks, decision and timings
- `events.jsonl`: browser-side errors and camera details
- `snapshots/` and `annotated/`: about one frame per second plus every decision
  change, raw and with the overlay drawn on
- `latest.jpg`: the most recent annotated frame

```bash
mix vision.report         # summary of the newest session + contact_sheet.jpg
```

The raw `snapshots/` folder is also the start of a dataset for the bike model.

## Measured on an M1 Pro (CPU only)

About 9 fps at 640px. Per frame: model ~46 ms, preprocessing ~4 ms, decoding ~7 ms,
round trip ~55 ms on localhost.

## Things worth knowing

- Nx's default pure-Elixir backend is far too slow for whole images (~700 ms to
  normalise one frame). OpenCV does that work instead; see the comments in
  `preprocess.ex` and `yolo_decoder.ex`.
- `Ortex.Model`'s `inspect` crashes on Elixir 1.20, so don't `IO.inspect` the model.
- The CoreML execution provider is a compile-time feature of Ortex
  (`features: ["coreml"]`); everything here uses the CPU provider.
- Postgres/Ecto was removed: nothing here needs a database.
