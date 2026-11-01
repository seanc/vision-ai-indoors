// The scavenger hunt's overlay. Boxes for the target class are big and gold,
// with how close they are to locking on; everything else is a thin grey box,
// so you can see what the model thinks it's looking at.
import {drawLabelledBox, fitOverlay} from "./viewer"

const TARGET = "#fbbf24" // amber
const FOUND = "#34d399" // green
const OTHER = "rgba(203,213,225,0.75)" // light grey

export function drawHuntOverlay(canvas, video, {frame, result}) {
  const view = fitOverlay(canvas, video, frame)
  if (!result?.tracks) return

  const hunt = result.hunt
  const framesToLock = hunt.frames_to_lock

  // Draw the other objects first so the target boxes sit on top.
  const tracks = [...result.tracks].sort((a, b) => Number(a.target) - Number(b.target))

  for (const track of tracks) {
    if (!track.target) {
      drawLabelledBox(view, track.box, {colour: OTHER, label: `${track.class} ${pct(track.score)}`, thickness: 1.5})
      continue
    }

    const isLocked = track.id === hunt.locked_track_id
    const found = isLocked && hunt.phase === "found"
    const progress = Math.min(track.age, framesToLock)

    const label = found
      ? `${hunt.target.emoji} found!`
      : `${hunt.target.emoji} ${track.class} ${pct(track.score)} · lock ${progress}/${framesToLock}`

    drawLabelledBox(view, track.box, {colour: found ? FOUND : TARGET, label, thickness: found ? 6 : 4})
  }
}

const pct = score => `${Math.round(score * 100)}%`
