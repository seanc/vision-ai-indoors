// The hallway/bike page's overlay: capture guides, the lane, and the
// tracked boxes the server sent back. Drawing helpers live in viewer.js.
import {drawLabelledBox, fillPolygon, fitOverlay, strokeLine} from "./viewer"

const ZONE_COLOURS = {
  my_half: "#34d399", // green
  oncoming_half: "#fbbf24", // amber
  off_path: "#94a3b8", // grey
}

export function drawBikeOverlay(canvas, video, {frame, lane, result, level}) {
  const view = fitOverlay(canvas, video, frame)

  if (lane) drawLane(view, lane, frame)
  drawGuides(view, lane, frame, level)

  for (const track of result?.tracks ?? []) {
    drawTrack(view, track, track.id === result.decision?.track_id)
  }
}

// The hand-drawn "path" (see zones.ex). Right half = my half, left half = oncoming.
function drawLane(view, lane, frame) {
  const toCanvas = ([x, y]) => view.point(x * frame.width, y * frame.height)
  const [topLeft, topRight, bottomRight, bottomLeft] = lane.polygon.map(toCanvas)
  const topCenter = toCanvas([lane.center_x, lane.horizon_y])
  const bottomCenter = toCanvas([lane.center_x, 1])

  fillPolygon(view, [topLeft, topCenter, bottomCenter, bottomLeft], {colour: ZONE_COLOURS.oncoming_half})
  fillPolygon(view, [topCenter, topRight, bottomRight, bottomCenter], {colour: ZONE_COLOURS.my_half})
  strokeLine(view, topCenter, bottomCenter, {colour: "rgba(255,255,255,0.6)", width: 2, dash: [8, 8]})
}

// Capture aids: line the far end of the hallway/path up with where these cross.
// The horizon line turns green when the phone reports it's level.
function drawGuides(view, lane, frame, level) {
  const [, horizonY] = view.point(0, (lane?.horizon_y ?? 0.4) * frame.height)
  const [centerX] = view.point((lane?.center_x ?? 0.5) * frame.width, 0)
  const {left, right, top, bottom} = view.picture

  const horizonColour = !level?.available
    ? "rgba(255,255,255,0.45)"
    : level.level
      ? "rgba(52,211,153,0.95)"
      : "rgba(248,113,113,0.95)"

  strokeLine(view, [left, horizonY], [right, horizonY], {colour: horizonColour})
  strokeLine(view, [centerX, top], [centerX, bottom], {colour: "rgba(255,255,255,0.25)"})
}

function drawTrack(view, track, isDecisionCause) {
  const colour = ZONE_COLOURS[track.zone] ?? ZONE_COLOURS.off_path

  // Label: "person #3 91%", plus "▲ 24%/s" while the box is growing.
  let label = `${track.class} #${track.id} ${Math.round(track.score * 100)}%`
  if (track.approaching) label += `  ▲ ${Math.round(track.growth_per_s * 100)}%/s`

  drawLabelledBox(view, track.box, {colour, label, thickness: isDecisionCause ? 4.5 : 2.5})

  // The point zones.ex uses to decide where the object is standing.
  const [footX, footY] = view.point((track.box.x1 + track.box.x2) / 2, track.box.y2)
  view.ctx.fillStyle = colour
  view.ctx.beginPath()
  view.ctx.arc(footX, footY, view.css(5), 0, Math.PI * 2)
  view.ctx.fill()
}
