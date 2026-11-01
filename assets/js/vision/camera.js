// Stage 1 of the pipeline: CAPTURE.
//
// Gets pictures into a <video> element (from the webcam, or from a video
// file so you can test without moving), and turns the current picture into
// a JPEG we can send to the server.

// Ask the browser for a camera. On a phone, "environment" means the back camera.
// Returns the camera's actual settings (resolution, which camera...) for the logs.
export async function startCamera(video) {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: false,
    video: {facingMode: "environment", width: {ideal: 1280}, height: {ideal: 720}},
  })

  video.srcObject = stream
  await video.play()
  await tryLockExposure(stream)

  const [track] = stream.getVideoTracks()
  return {label: track.label, ...track.getSettings()}
}

// Play a local video file instead of the camera. Same pipeline, no webcam needed.
export async function startVideoFile(video, file) {
  stopVideo(video)
  video.src = URL.createObjectURL(file)
  video.loop = true
  video.muted = true
  await video.play()
}

export function stopVideo(video) {
  if (video.srcObject) {
    video.srcObject.getTracks().forEach(track => track.stop())
    video.srcObject = null
  }
  if (video.src) {
    URL.revokeObjectURL(video.src)
    video.removeAttribute("src")
  }
}

// Draw the current video picture onto a hidden canvas, shrunk so it's at most
// `maxWidth` wide (the model only looks at 640x640 anyway, so sending more
// is wasted bandwidth), then encode it as JPEG.
//
// Returns {jpeg: ArrayBuffer, width, height}. Boxes come back from the server
// in these width/height pixels.
export async function captureJpeg(video, canvas, {maxWidth = 640, quality = 0.7} = {}) {
  const scale = Math.min(1, maxWidth / video.videoWidth)
  const width = Math.round(video.videoWidth * scale)
  const height = Math.round(video.videoHeight * scale)

  canvas.width = width
  canvas.height = height
  canvas.getContext("2d").drawImage(video, 0, 0, width, height)

  const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", quality))
  return {jpeg: await blob.arrayBuffer(), width, height}
}

// Auto-exposure makes the picture pump brighter/darker as things move, which
// changes what the model sees. Lock it if the browser lets us (mostly Android
// Chrome; Safari and laptop webcams usually don't support this).
async function tryLockExposure(stream) {
  const [track] = stream.getVideoTracks()
  const supported = track.getCapabilities?.().exposureMode || []

  if (supported.includes("manual")) {
    try {
      await track.applyConstraints({advanced: [{exposureMode: "manual"}]})
    } catch (_error) {
      // Not fatal, carry on with auto exposure.
    }
  }
}
