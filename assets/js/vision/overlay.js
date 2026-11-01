// Draws everything on top of the video: capture guides, the lane, and the
// tracked boxes the server sent back.
//
// The canvas is sized to the frame we SENT (e.g. 640x360), so the server's
// box coordinates can be drawn directly with no conversion. CSS then
// stretches the canvas to cover the video.

const ZONE_COLOURS = {
  my_half: "#34d399", // green
  oncoming_half: "#fbbf24", // amber
  off_path: "#94a3b8", // grey
}

export function drawOverlay(canvas, {width, height, lane, result, level}) {
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width
    canvas.height = height
  }

  const ctx = canvas.getContext("2d")
  ctx.clearRect(0, 0, width, height)

  if (lane) drawLane(ctx, lane, width, height)
  drawGuides(ctx, lane, width, height, level)

  for (const track of result?.tracks ?? []) {
    drawTrack(ctx, track, track.id === result.decision?.track_id)
  }
}

// The hand-drawn "path" (see zones.ex). Right half = my half, left half = oncoming.
function drawLane(ctx, lane, width, height) {
  const [topLeft, topRight, bottomRight, bottomLeft] = lane.polygon.map(([x, y]) => [x * width, y * height])
  const topCenter = [lane.center_x * width, lane.horizon_y * height]
  const bottomCenter = [lane.center_x * width, height]

  fillShape(ctx, [topLeft, topCenter, bottomCenter, bottomLeft], ZONE_COLOURS.oncoming_half)
  fillShape(ctx, [topCenter, topRight, bottomRight, bottomCenter], ZONE_COLOURS.my_half)

  // Dashed centre line between the halves.
  ctx.save()
  ctx.setLineDash([8, 8])
  ctx.strokeStyle = "rgba(255,255,255,0.6)"
  ctx.lineWidth = 2
  line(ctx, topCenter, bottomCenter)
  ctx.restore()
}

// Capture aids: line the far end of the hallway/path up with where these cross.
// The horizon line turns green when the phone reports it's level.
function drawGuides(ctx, lane, width, height, level) {
  const horizonY = (lane?.horizon_y ?? 0.4) * height
  const centerX = (lane?.center_x ?? 0.5) * width

  ctx.save()
  ctx.lineWidth = 1.5
  ctx.strokeStyle = level?.available
    ? level.level
      ? "rgba(52,211,153,0.95)"
      : "rgba(248,113,113,0.95)"
    : "rgba(255,255,255,0.45)"
  line(ctx, [0, horizonY], [width, horizonY])
  ctx.strokeStyle = "rgba(255,255,255,0.25)"
  line(ctx, [centerX, 0], [centerX, height])
  ctx.restore()
}

function drawTrack(ctx, track, isDecisionCause) {
  const {x1, y1, x2, y2} = track.box
  const colour = ZONE_COLOURS[track.zone] ?? ZONE_COLOURS.off_path

  ctx.save()
  ctx.strokeStyle = colour
  ctx.lineWidth = isDecisionCause ? 4 : 2
  ctx.strokeRect(x1, y1, x2 - x1, y2 - y1)

  // The point zones.ex uses to decide where the object is standing.
  ctx.fillStyle = colour
  ctx.beginPath()
  ctx.arc((x1 + x2) / 2, y2, 5, 0, Math.PI * 2)
  ctx.fill()

  // Label: "person #3 91%", plus "▲ 24%/s" while the box is growing.
  let label = `${track.class} #${track.id} ${Math.round(track.score * 100)}%`
  if (track.approaching) label += `  ▲ ${Math.round(track.growth_per_s * 100)}%/s`

  ctx.font = "600 13px ui-sans-serif, system-ui, sans-serif"
  const labelWidth = ctx.measureText(label).width + 10
  const labelY = Math.max(0, y1 - 20)
  ctx.fillRect(x1, labelY, labelWidth, 20)
  ctx.fillStyle = "#0b1120"
  ctx.fillText(label, x1 + 5, labelY + 14)
  ctx.restore()
}

function fillShape(ctx, points, colour) {
  ctx.save()
  ctx.globalAlpha = 0.14
  ctx.fillStyle = colour
  ctx.beginPath()
  points.forEach(([x, y], i) => (i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)))
  ctx.closePath()
  ctx.fill()
  ctx.restore()
}

function line(ctx, [x1, y1], [x2, y2]) {
  ctx.beginPath()
  ctx.moveTo(x1, y1)
  ctx.lineTo(x2, y2)
  ctx.stroke()
}
