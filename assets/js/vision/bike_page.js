// The hallway/bike page: draws the lane, boxes and decision. The camera,
// channel and frame loop are shared with the other experiments (session.js).
import {drawBikeOverlay} from "./bike_overlay"
import {startSession} from "./session"

const DECISION_STYLES = {
  clear: {label: "CLEAR", classes: ["bg-emerald-500/15", "text-emerald-300", "ring-emerald-400/40"]},
  caution: {label: "CAUTION", classes: ["bg-amber-500/15", "text-amber-300", "ring-amber-400/40"]},
  yield: {label: "YIELD", classes: ["bg-rose-500/20", "text-rose-300", "ring-rose-400/50"]},
}

export function startBikePage(root) {
  const $ = id => root.querySelector(`#${id}`)
  const el = {
    decision: $("decision"),
    decisionLevel: $("decision-level"),
    decisionReason: $("decision-reason"),
    decisionConfidence: $("decision-confidence"),
    hudDecision: $("hud-decision"),
    hudReason: $("hud-reason"),
    tracks: $("track-list"),
    tracksEmpty: $("track-list-empty"),
    level: $("level"),
  }

  let lane = null

  startSession(root, {
    topic: "vision",
    onJoin: joinReply => (lane = joinReply.lane),
    onResult: result => {
      renderDecision(result.decision)
      renderTracks(result.tracks)
    },
    onDraw: ({state, el: session, orientation}) => {
      if (state.lastFrame) {
        drawBikeOverlay(session.overlay, session.video, {
          frame: state.lastFrame,
          lane,
          result: state.lastResult,
          level: orientation.level(),
        })
      }
      renderLevel(orientation.level())
    },
  })

  function renderDecision(decision) {
    const style = DECISION_STYLES[decision.level]

    for (const target of [el.decision, el.hudDecision]) {
      Object.values(DECISION_STYLES).forEach(s => target.classList.remove(...s.classes))
      target.classList.add(...style.classes)
    }

    el.decisionLevel.textContent = style.label
    el.decisionReason.textContent = decision.reason
    el.decisionConfidence.style.width = `${Math.round(decision.confidence * 100)}%`
    el.hudDecision.textContent = style.label
    el.hudReason.textContent = decision.reason
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
}
