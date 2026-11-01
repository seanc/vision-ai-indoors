// Talks to IndoorsExperimentsWeb.VisionChannel over a Phoenix Channel (a WebSocket).
import {Socket} from "phoenix"

// Join a channel for this tab. `topic` picks the experiment ("vision" for
// the bike/hallway page, "hunt" for the scavenger hunt). Resolves with the
// server's join reply.
//
// `clientInfo` (browser, screen size...) is saved with the session recording,
// so we know what device a recording came from.
export function connect(topic, clientInfo) {
  const socket = new Socket("/socket")
  socket.connect()

  // Every tab gets its own session id, and so its own tracker on the server.
  const sessionId = crypto.randomUUID?.() ?? String(Math.random()).slice(2)
  const channel = socket.channel(`${topic}:${sessionId}`, clientInfo)

  return new Promise((resolve, reject) => {
    channel
      .join()
      .receive("ok", joinReply => resolve({channel, joinReply}))
      .receive("error", reject)
      .receive("timeout", () => reject(new Error("join timed out")))
  })
}

// Send one frame and wait for its results.
//
// The message is binary so the JPEG is sent as-is:
//
//   [4 bytes: header length][header as JSON text][JPEG bytes]
//
// The server takes it apart with Elixir binary pattern matching
// (see `unpack/1` in vision_channel.ex).
export function sendFrame(channel, jpeg, meta) {
  const header = new TextEncoder().encode(JSON.stringify(meta))
  const message = new Uint8Array(4 + header.length + jpeg.byteLength)

  new DataView(message.buffer).setUint32(0, header.length) // big-endian, like Elixir's ::32
  message.set(header, 4)
  message.set(new Uint8Array(jpeg), 4 + header.length)

  return new Promise((resolve, reject) => {
    channel
      .push("frame", message.buffer, 5000)
      .receive("ok", resolve)
      .receive("error", reject)
      .receive("timeout", () => reject(new Error("frame timed out")))
  })
}

// Tell the server about something worth recording (an error, camera
// details...). On a phone there's no console to look at, so this is how
// problems get noticed: they land in the session's events.jsonl.
export function sendLog(channel, level, message, details = {}) {
  channel?.push("client_log", {level, message, details, t: Date.now()})
}
