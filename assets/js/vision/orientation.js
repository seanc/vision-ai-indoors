// Phone orientation, sent with every frame and used for the level indicator.
//
// Two browser events are involved:
//
//   * deviceorientation gives alpha/beta/gamma angles. We send these raw with
//     each frame so recorded data can be filtered later.
//   * devicemotion gives the gravity vector. We use it for the level
//     indicator, because the angles above get unreliable exactly when the
//     phone is held upright (which is how we hold it).
//
// A laptop has neither sensor, so `latest()` just stays null.

// How far off level is still "level", in degrees.
const MAX_ROLL = 4
const MAX_PITCH = 10

export function watchOrientation() {
  const state = {angles: null, roll: null, pitch: null}

  window.addEventListener("deviceorientation", event => {
    if (event.beta === null) return
    state.angles = {alpha: event.alpha, beta: event.beta, gamma: event.gamma}
  })

  window.addEventListener("devicemotion", event => {
    const g = event.accelerationIncludingGravity
    if (!g || g.x === null) return
    Object.assign(state, rollAndPitch(g))
  })

  return {
    // What we attach to each frame. null on a laptop.
    latest: () => state.angles && {...state.angles, roll: state.roll, pitch: state.pitch},
    level: () => levelStatus(state),
  }
}

// iOS only sends these events after the user taps something and agrees.
// Call this from a click handler.
export async function requestOrientationPermission() {
  for (const Event of [window.DeviceOrientationEvent, window.DeviceMotionEvent]) {
    if (Event && typeof Event.requestPermission === "function") {
      try {
        await Event.requestPermission()
      } catch (_error) {
        // The user said no. Everything still works, minus the level indicator.
      }
    }
  }
}

// Gravity always points at the floor. If the phone is held level and pointing
// forward, gravity runs straight down the screen. So:
//
//   * roll  = how much gravity leans left/right across the screen
//   * pitch = how much gravity points into/out of the screen (camera tilted up/down)
//
// The sensor's x/y axes are fixed to the phone in portrait, so we first rotate
// them by the screen's rotation to get "across" and "down" for how the phone
// is actually being held.
function rollAndPitch({x, y, z}) {
  const angle = ((screen.orientation?.angle ?? window.orientation ?? 0) * Math.PI) / 180
  const across = x * Math.cos(angle) + y * Math.sin(angle)
  const down = -x * Math.sin(angle) + y * Math.cos(angle)

  const toDegrees = radians => (radians * 180) / Math.PI
  const roll = toDegrees(Math.atan2(across, Math.abs(down)))
  const pitch = toDegrees(Math.atan2(z, Math.hypot(across, down)))

  return {roll, pitch}
}

function levelStatus({roll, pitch}) {
  if (roll === null) return {available: false}

  return {
    available: true,
    roll,
    pitch,
    level: Math.abs(roll) <= MAX_ROLL && Math.abs(pitch) <= MAX_PITCH,
  }
}
