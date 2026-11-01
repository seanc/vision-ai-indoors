// Everything a camera page needs, whatever the experiment:
//
//   * join a channel on the server
//   * the Start camera / video file / Stop buttons
//   * the frame loop: grab a frame -> send it -> wait for the reply -> repeat
//   * the latency numbers, status line and error reporting
//
// Each experiment page (bike_page.js, hunt_page.js) calls `startSession` and
// only has to draw its own results in `onResult` / `onDraw`.
//
// Only one frame is ever in flight. If the server takes 150ms, we simply
// send fewer frames, instead of queueing up a backlog that makes the
// overlay fall further and further behind the video.
import {captureJpeg, startCamera, startVideoFile, stopVideo} from "./camera"
import {connect, sendFrame, sendLog} from "./connection"
import {requestOrientationPermission, watchOrientation} from "./orientation"
import {setupFocusMode} from "./viewer"

export function startSession(root, {topic, joinParams = {}, onJoin = () => {}, onResult = () => {}, onDraw = () => {}}) {
  const $ = id => root.querySelector(`#${id}`)
  const el = {
    stage: $("stage"),
    video: $("video"),
    overlay: $("overlay"),
    captureCanvas: $("capture-canvas"),
    empty: $("stage-empty"),
    startCamera: $("start-camera"),
    videoFile: $("video-file"),
    stop: $("stop"),
    fps: $("fps-select"),
    status: $("status"),
    timeline: $("latency-bar"),
    stats: {
      fps: $("stat-fps"),
      roundTrip: $("stat-round-trip"),
      server: $("stat-server"),
      model: $("stat-model"),
      size: $("stat-size"),
      frame: $("stat-frame"),
    },
  }

  const orientation = watchOrientation()
  const state = {
    channel: null,
    running: false,
    seq: 0,
    lastResult: null,
    // Size of the last frame we sent; the server's boxes are in these pixels.
    lastFrame: null,
    doneTimes: [],
    // The browser's own timings for the last frame. Sent along with the next
    // frame so the server's recording has the full picture.
    lastClientStats: null,
  }

  connect(topic, {...clientInfo(), ...joinParams})
    .then(({channel, joinReply}) => {
      state.channel = channel
      const recording = joinReply.recording ? " (recording to tmp/sessions)" : ""
      setStatus(
        joinReply.model_ready ? `Connected, model loaded${recording}` : "Connected, but no model: run scripts/export_yolo.sh",
        joinReply.model_ready,
      )
      onJoin(joinReply)
    })
    .catch(() => setStatus("Could not connect to the server", false))

  // Anything that blows up in the page gets reported to the server too.
  window.addEventListener("error", event => sendLog(state.channel, "error", event.message, {source: event.filename, line: event.lineno}))
  window.addEventListener("unhandledrejection", event => sendLog(state.channel, "error", String(event.reason)))

  setupFocusMode(el.stage, root.querySelectorAll("[data-focus-toggle]"))

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
  // so it keeps up with resizes and focus mode between replies.
  const redraw = () => {
    onDraw({state, el, orientation})
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
      renderStats(result, {captureMs, roundTripMs, bytes: jpeg.byteLength})
      state.lastClientStats = {
        round_trip_ms: Math.round(roundTripMs),
        capture_ms: Math.round(captureMs),
        fps: state.doneTimes.length,
        video_size: [el.video.videoWidth, el.video.videoHeight],
        sent_size: [width, height],
      }

      if (result.error) {
        setStatus(result.error === "no_model" ? "No model loaded: run scripts/export_yolo.sh" : `Server: ${result.error}`, false)
      } else {
        onResult(result)
      }
    } catch (error) {
      setStatus(`Frame failed: ${error.message ?? error.reason ?? "unknown error"}`, false)
    }
  }

  // --- Latency panel ------------------------------------------------------------

  function renderStats(result, {captureMs, roundTripMs, bytes}) {
    const now = performance.now()
    state.doneTimes = [...state.doneTimes.filter(t => now - t < 1000), now]

    setText(el.stats.fps, state.doneTimes.length)
    setText(el.stats.roundTrip, `${Math.round(roundTripMs)} ms`)
    setText(el.stats.server, `${Math.round(result.server_ms)} ms`)
    setText(el.stats.model, result.timings ? `${Math.round(result.timings.model_ms)} ms` : "–")
    setText(el.stats.size, `${Math.round(bytes / 1024)} KB`)
    setText(el.stats.frame, `#${result.frame_number}`)

    if (el.timeline && result.timings) {
      renderTimeline({captureMs, roundTripMs, serverMs: result.server_ms, timings: result.timings})
    }
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

  function setStatus(text, ok) {
    // Only report a problem once, not on every frame it keeps happening.
    if (!ok && el.status.textContent !== text) sendLog(state.channel, "warning", text)
    el.status.textContent = text
    el.status.dataset.ok = ok
  }

  return {
    state,
    el,
    orientation,
    // Send an extra event to this page's channel (e.g. "skip" in the hunt).
    // Returns the Phoenix push, so callers can `.receive("ok", ...)`.
    push: (event, payload = {}) => state.channel?.push(event, payload),
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

function setText(element, text) {
  if (element) element.textContent = text
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))
