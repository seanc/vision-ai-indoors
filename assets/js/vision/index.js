// The camera page. Wires the pieces together and runs the frame loop:
//
//   grab a frame -> send it -> wait for the reply -> remember it -> repeat
//
// Only one frame is ever in flight. If the server takes 150ms, we simply
// send fewer frames, instead of queueing up a backlog that makes the
// overlay fall further and further behind the video.
import {captureJpeg, startCamera, startVideoFile, stopVideo} from "./camera"
import {connect, sendFrame, sendLog} from "./connection"
import {drawOverlay} from "./overlay"
import {requestOrientationPermission, watchOrientation} from "./orientation"

export function startVisionPage(root) {
  const $ = id => root.querySelector(`#${id}`)
  const el = {
    video: $("video"),
    overlay: $("overlay"),
    captureCanvas: $("capture-canvas"),
    empty: $("stage-empty"),
    startCamera: $("start-camera"),
    videoFile: $("video-file"),
    stop: $("stop"),
    fps: $("fps-select"),
    status: $("status"),
    decision: $("decision"),
    decisionLevel: $("decision-level"),
    decisionReason: $("decision-reason"),
    decisionConfidence: $("decision-confidence"),
    stats: {
      fps: $("stat-fps"),
      roundTrip: $("stat-round-trip"),
      server: $("stat-server"),
      model: $("stat-model"),
      size: $("stat-size"),
      frame: $("stat-frame"),
    },
    timeline: $("latency-bar"),
    tracks: $("track-list"),
    tracksEmpty: $("track-list-empty"),
    level: $("level"),
  }

  const orientation = watchOrientation()
  const state = {
    channel: null,
    lane: null,
    running: false,
    seq: 0,
    lastResult: null,
    lastFrame: null,
    doneTimes: [],
    // The browser's own timings for the last frame. Sent along with the next
    // frame so the server's recording has the full picture.
    lastClientStats: null,
  }

  connect(clientInfo())
    .then(({channel, joinReply}) => {
      state.channel = channel
      state.lane = joinReply.lane
      const recording = joinReply.recording ? " (recording to tmp/sessions)" : ""
      setStatus(
        joinReply.model_ready ? `Connected, model loaded${recording}` : "Connected, but no model: run scripts/export_yolo.sh",
        joinReply.model_ready,
      )
    })
    .catch(() => setStatus("Could not connect to the server", false))

  // Anything that blows up in the page gets reported to the server too.
  window.addEventListener("error", event => sendLog(state.channel, "error", event.message, {source: event.filename, line: event.lineno}))
  window.addEventListener("unhandledrejection", event => sendLog(state.channel, "error", String(event.reason)))

  el.startCamera.addEventListener("click", async () => {
    // Ask for the camera BEFORE waiting on the motion-sensor prompt: on iOS a
    // permission dialog can use up the tap, and then the camera request is refused.
    const camera = startCamera(el.video)
    await requestOrientationPermission()
    try {
      const settings = await camera
      sendLog(state.channel, "info", "camera started", settings)
      begin()
    } catch (error) {
      setStatus(`Camera unavailable: ${error.message}`, false)
    }
  })

  el.videoFile.addEventListener("change", async () => {
    const [file] = el.videoFile.files
    if (!file) return
    await startVideoFile(el.video, file)
    sendLog(state.channel, "info", "video file started", {name: file.name, size: file.size})
    begin()
  })

  el.stop.addEventListener("click", () => {
    state.running = false
    stopVideo(el.video)
    el.empty.classList.remove("hidden")
    el.stop.disabled = true
  })

  // Redraw the overlay every screen refresh using the latest result we have,
  // so the guides and level line stay live between replies.
  const redraw = () => {
    if (state.lastFrame) {
      drawOverlay(el.overlay, {...state.lastFrame, lane: state.lane, result: state.lastResult, level: orientation.level()})
    }
    renderLevel(orientation.level())
    requestAnimationFrame(redraw)
  }
  requestAnimationFrame(redraw)

  function begin() {
    el.empty.classList.add("hidden")
    el.stop.disabled = false
    if (!state.running) {
      state.running = true
      loop()
    }
  }

  async function loop() {
    while (state.running) {
      const frameStarted = performance.now()

      if (state.channel && el.video.readyState >= 2) {
        await processOneFrame(frameStarted)
      }

      // Wait out the rest of this frame's time slot to hit the chosen fps.
      const slot = 1000 / Number(el.fps.value)
      await sleep(Math.max(0, slot - (performance.now() - frameStarted)))
    }
  }

  async function processOneFrame(frameStarted) {
    const {jpeg, width, height} = await captureJpeg(el.video, el.captureCanvas)
    const captureMs = performance.now() - frameStarted
    const meta = {seq: ++state.seq, t: Date.now(), orientation: orientation.latest(), client: state.lastClientStats}

    const sentAt = performance.now()
    try {
      const result = await sendFrame(state.channel, jpeg, meta)
      const roundTripMs = performance.now() - sentAt

      state.lastResult = result
      state.lastFrame = {width, height}
      state.lastClientStats = {
        round_trip_ms: Math.round(roundTripMs),
        capture_ms: Math.round(captureMs),
        fps: state.doneTimes.length,
        video_size: [el.video.videoWidth, el.video.videoHeight],
        sent_size: [width, height],
      }
      renderResult(result, {captureMs, roundTripMs, bytes: jpeg.byteLength})
    } catch (error) {
      setStatus(`Frame failed: ${error.message ?? error.reason ?? "unknown error"}`, false)
    }
  }

  // --- Rendering the side panel ---------------------------------------------

  function renderResult(result, {captureMs, roundTripMs, bytes}) {
    const now = performance.now()
    state.doneTimes = [...state.doneTimes.filter(t => now - t < 1000), now]

    el.stats.fps.textContent = state.doneTimes.length
    el.stats.roundTrip.textContent = `${Math.round(roundTripMs)} ms`
    el.stats.server.textContent = `${Math.round(result.server_ms)} ms`
    el.stats.model.textContent = result.timings ? `${Math.round(result.timings.model_ms)} ms` : "–"
    el.stats.size.textContent = `${Math.round(bytes / 1024)} KB`
    el.stats.frame.textContent = `#${result.frame_number}`

    if (result.error) {
      setStatus(result.error === "no_model" ? "No model loaded: run scripts/export_yolo.sh" : `Server: ${result.error}`, false)
      return
    }

    renderTimeline({captureMs, roundTripMs, serverMs: result.server_ms, timings: result.timings})
    renderDecision(result.decision)
    renderTracks(result.tracks)
  }

  const DECISION_STYLES = {
    clear: {label: "CLEAR", classes: ["bg-emerald-500/15", "text-emerald-300", "ring-emerald-400/40"]},
    caution: {label: "CAUTION", classes: ["bg-amber-500/15", "text-amber-300", "ring-amber-400/40"]},
    yield: {label: "YIELD", classes: ["bg-rose-500/20", "text-rose-300", "ring-rose-400/50"]},
  }

  function renderDecision(decision) {
    const style = DECISION_STYLES[decision.level]
    Object.values(DECISION_STYLES).forEach(s => el.decision.classList.remove(...s.classes))
    el.decision.classList.add(...style.classes)
    el.decision.dataset.level = decision.level
    el.decisionLevel.textContent = style.label
    el.decisionReason.textContent = decision.reason
    el.decisionConfidence.style.width = `${Math.round(decision.confidence * 100)}%`
  }

  // Where did this frame's time go? Each segment is a share of the full cycle.
  function renderTimeline({captureMs, roundTripMs, serverMs, timings}) {
    const pipelineMs = timings.preprocess_ms + timings.model_ms + timings.decode_ms
    const segments = {
      capture: captureMs,
      network: Math.max(0, roundTripMs - serverMs),
      preprocess: timings.preprocess_ms,
      model: timings.model_ms,
      decode: timings.decode_ms,
      track: Math.max(0, serverMs - pipelineMs),
    }
    const total = Object.values(segments).reduce((a, b) => a + b, 0) || 1

    for (const [name, ms] of Object.entries(segments)) {
      const segment = el.timeline.querySelector(`[data-segment="${name}"]`)
      segment.style.width = `${(ms / total) * 100}%`
      segment.title = `${name}: ${ms.toFixed(1)} ms`
    }
  }

  function renderTracks(tracks) {
    el.tracksEmpty.classList.toggle("hidden", tracks.length > 0)
    el.tracks.replaceChildren(
      ...tracks.map(track => {
        const row = document.createElement("li")
        row.className = "flex items-center justify-between gap-3 rounded-lg bg-white/[0.03] px-3 py-2 ring-1 ring-white/5"

        const name = document.createElement("span")
        name.className = "font-medium text-slate-200"
        name.textContent = `${track.class} #${track.id}`

        const detail = document.createElement("span")
        detail.className = "font-mono text-xs text-slate-400"
        const growth = `${track.growth_per_s >= 0 ? "+" : ""}${Math.round(track.growth_per_s * 100)}%/s`
        detail.textContent = `${track.zone.replace("_", " ")} · ${growth}${track.approaching ? " ▲" : ""}`

        row.append(name, detail)
        return row
      }),
    )
  }

  function renderLevel(level) {
    if (!level.available) {
      el.level.textContent = "No motion sensor (laptop). Level check off."
      el.level.className = "text-xs text-slate-500"
    } else {
      el.level.textContent = `roll ${level.roll.toFixed(0)}°  pitch ${level.pitch.toFixed(0)}°  ${level.level ? "level" : "tilt to level"}`
      el.level.className = `text-xs font-mono ${level.level ? "text-emerald-300" : "text-rose-300"}`
    }
  }

  function setStatus(text, ok) {
    // Only report a problem once, not on every frame it keeps happening.
    if (!ok && el.status.textContent !== text) sendLog(state.channel, "warning", text)
    el.status.textContent = text
    el.status.dataset.ok = ok
  }
}

// What device is this? Saved in the recording's session.json.
function clientInfo() {
  return {
    user_agent: navigator.userAgent,
    screen: [screen.width, screen.height],
    viewport: [window.innerWidth, window.innerHeight],
    pixel_ratio: window.devicePixelRatio,
    secure_context: window.isSecureContext,
    has_orientation_sensor: "DeviceOrientationEvent" in window,
  }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
