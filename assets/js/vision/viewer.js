// The "viewer": the video plus the canvas drawn on top of it.
//
// Two jobs:
//
// 1. Keep the overlay sharp and readable. The server's boxes are in the
//    pixels of the frame we SENT (e.g. 640x360). If we drew at that size and
//    let CSS stretch the canvas, labels would shrink to a few pixels on a
//    phone. Instead the canvas always matches its on-screen size (times the
//    screen's pixel density), and `fitOverlay` gives a conversion from frame
//    pixels to canvas pixels.
//
// 2. Focus mode: the stage fills the whole screen, with a small heads-up
//    display on top. iPhone Safari won't make a page element truly
//    fullscreen, so focus mode is just CSS (`data-focus="true"` on the stage),
//    plus the real Fullscreen API where the browser has it.

// Label text size in CSS pixels; multiplied by the pixel density when drawing.
const LABEL_SIZE = 15

// Resize the canvas to its on-screen size and work out where the video
// picture actually sits inside the element. With `object-contain` the picture
// is letterboxed: a portrait phone camera in a landscape box has black bars
// at the sides, and the boxes must line up with the picture, not the bars.
//
// Returns a "view": the 2D context plus `point(x, y)` / `size(n)` helpers
// that turn frame pixels into canvas pixels.
export function fitOverlay(canvas, video, frame) {
  const dpr = window.devicePixelRatio || 1
  const cssWidth = canvas.clientWidth
  const cssHeight = canvas.clientHeight
  const width = Math.round(cssWidth * dpr)
  const height = Math.round(cssHeight * dpr)

  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width
    canvas.height = height
  }

  // Where is the picture inside the element (in CSS pixels)?
  const pictureAspect = (video.videoWidth || frame.width) / (video.videoHeight || frame.height)
  const boxAspect = cssWidth / cssHeight
  const pictureWidth = pictureAspect > boxAspect ? cssWidth : cssHeight * pictureAspect
  const pictureHeight = pictureAspect > boxAspect ? cssWidth / pictureAspect : cssHeight
  const offsetX = (cssWidth - pictureWidth) / 2
  const offsetY = (cssHeight - pictureHeight) / 2

  // One frame pixel = this many canvas pixels.
  const scale = (pictureWidth / frame.width) * dpr

  const ctx = canvas.getContext("2d")
  ctx.clearRect(0, 0, width, height)

  return {
    ctx,
    dpr,
    // Frame pixels -> canvas pixels.
    point: (x, y) => [offsetX * dpr + x * scale, offsetY * dpr + y * scale],
    // A length in frame pixels -> canvas pixels.
    length: n => n * scale,
    // A size in CSS pixels (line widths, fonts) -> canvas pixels.
    css: n => n * dpr,
    // The picture's corners in canvas pixels, for drawing full-width lines.
    picture: {
      left: offsetX * dpr,
      top: offsetY * dpr,
      right: (offsetX + pictureWidth) * dpr,
      bottom: (offsetY + pictureHeight) * dpr,
    },
  }
}

// A box with a filled label above it: the basic unit of every overlay.
export function drawLabelledBox(view, box, {colour, label, thickness = 2.5, textColour = "#0b1120"}) {
  const {ctx} = view
  const [x1, y1] = view.point(box.x1, box.y1)
  const [x2, y2] = view.point(box.x2, box.y2)

  ctx.save()
  ctx.strokeStyle = colour
  ctx.lineWidth = view.css(thickness)
  ctx.strokeRect(x1, y1, x2 - x1, y2 - y1)

  if (label) {
    ctx.font = `600 ${view.css(LABEL_SIZE)}px ui-sans-serif, system-ui, sans-serif`
    const padding = view.css(6)
    const labelHeight = view.css(LABEL_SIZE + 9)
    const labelWidth = ctx.measureText(label).width + padding * 2
    // Above the box if there's room, otherwise just inside its top edge.
    const labelY = y1 - labelHeight >= view.picture.top ? y1 - labelHeight : y1

    ctx.fillStyle = colour
    ctx.fillRect(x1, labelY, labelWidth, labelHeight)
    ctx.fillStyle = textColour
    ctx.textBaseline = "middle"
    ctx.fillText(label, x1 + padding, labelY + labelHeight / 2)
  }
  ctx.restore()
}

export function strokeLine(view, from, to, {colour, width = 1.5, dash = null}) {
  const {ctx} = view
  ctx.save()
  ctx.strokeStyle = colour
  ctx.lineWidth = view.css(width)
  if (dash) ctx.setLineDash(dash.map(view.css))
  ctx.beginPath()
  ctx.moveTo(...from)
  ctx.lineTo(...to)
  ctx.stroke()
  ctx.restore()
}

export function fillPolygon(view, points, {colour, alpha = 0.14}) {
  const {ctx} = view
  ctx.save()
  ctx.globalAlpha = alpha
  ctx.fillStyle = colour
  ctx.beginPath()
  points.forEach(([x, y], i) => (i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)))
  ctx.closePath()
  ctx.fill()
  ctx.restore()
}

// Wire up the focus-mode toggle. `stage` gets data-focus="true|false" and
// the template's Tailwind classes do the rest.
export function setupFocusMode(stage, toggleButtons) {
  const setFocus = on => {
    stage.dataset.focus = on
    document.body.classList.toggle("overflow-hidden", on)

    // Real fullscreen where the browser supports it for any element
    // (desktop, Android). On iPhone this doesn't exist and CSS does the job.
    if (on && stage.requestFullscreen && !document.fullscreenElement) {
      stage.requestFullscreen().catch(() => {})
    } else if (!on && document.fullscreenElement) {
      document.exitFullscreen().catch(() => {})
    }
  }

  toggleButtons.forEach(button => button.addEventListener("click", () => setFocus(stage.dataset.focus !== "true")))
  document.addEventListener("keydown", event => event.key === "Escape" && setFocus(false))
  document.addEventListener("fullscreenchange", () => {
    if (!document.fullscreenElement && stage.dataset.focus === "true") setFocus(false)
  })
}
