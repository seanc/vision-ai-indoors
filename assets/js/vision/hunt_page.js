// The scavenger hunt page. The camera, channel and frame loop are shared
// (session.js); this file only shows the game: the target, the lock-on bar,
// what the model is seeing, the score, and a "Found it!" pop-up.
import {drawHuntOverlay} from "./hunt_overlay"
import {startSession} from "./session"

export function startHuntPage(root) {
  const $ = id => document.getElementById(id)
  const el = {
    targetName: [$("hunt-target-name"), $("hud-target-name")],
    targetEmoji: [$("hunt-target-emoji"), $("hud-target-emoji")],
    timer: [$("hunt-timer"), $("hud-timer")],
    score: [$("hunt-score"), $("hud-score")],
    lockBar: [$("hunt-lock-bar"), $("hud-lock-bar")],
    skip: [$("hunt-skip"), $("hud-skip")],
    targetPoints: $("hunt-target-points"),
    lockLabel: $("hunt-lock-label"),
    seeing: $("hunt-seeing"),
    seeingEmpty: $("hunt-seeing-empty"),
    found: $("hunt-found-list"),
    foundEmpty: $("hunt-found-empty"),
    celebrate: $("hunt-celebrate"),
    celebrateEmoji: $("hunt-celebrate-emoji"),
    celebrateDetail: $("hunt-celebrate-detail"),
  }

  // How many finds we've already celebrated, so each one pops up once.
  let celebrated = 0

  const session = startSession(root, {
    topic: "hunt",
    // Debugging aid: /hunt?target=bus starts with that target.
    joinParams: {target: new URLSearchParams(location.search).get("target")},
    onResult: result => {
      renderHunt(result.hunt)
      renderSeeing(result.tracks, result.hunt.target.class)
    },
    onDraw: ({state, el: stage}) => {
      if (state.lastFrame) {
        drawHuntOverlay(stage.overlay, stage.video, {frame: state.lastFrame, result: state.lastResult})
      }
    },
  })

  el.skip.forEach(button =>
    button.addEventListener("click", () => {
      session.push("skip", {t: Date.now()})?.receive("ok", reply => renderHunt(reply.hunt))
    }),
  )

  function renderHunt(hunt) {
    const {target} = hunt
    setAll(el.targetName, `a ${target.class}`)
    setAll(el.targetEmoji, target.emoji)
    setAll(el.timer, hunt.seconds_hunting.toFixed(1))
    setAll(el.score, hunt.score)
    el.targetPoints.textContent = `${target.points} ${target.points === 1 ? "point" : "points"}`
    el.lockBar.forEach(bar => (bar.style.width = `${Math.round(hunt.lock * 100)}%`))
    el.lockLabel.textContent =
      hunt.phase === "found" ? "locked!" : hunt.lock > 0 ? `${Math.round(hunt.lock * hunt.frames_to_lock)} of ${hunt.frames_to_lock} frames` : "not seen yet"

    renderFound(hunt.found)

    if (hunt.found_count > celebrated) {
      celebrated = hunt.found_count
      celebrate(hunt.found[0])
    }
  }

  // Chips for every class in view, the target first and highlighted. If you're
  // pointing at a cup and it says "bowl", this is where you'll notice.
  function renderSeeing(tracks, targetClass) {
    const counts = {}
    tracks.forEach(track => (counts[track.class] = (counts[track.class] ?? 0) + 1))
    const classes = Object.keys(counts).sort((a, b) => (b === targetClass) - (a === targetClass))

    el.seeingEmpty.classList.toggle("hidden", classes.length > 0)
    el.seeing.replaceChildren(
      ...classes.map(name => {
        const chip = document.createElement("li")
        chip.className =
          name === targetClass
            ? "rounded-full bg-amber-400/20 px-3 py-1 font-semibold text-amber-200 ring-1 ring-amber-300/40"
            : "rounded-full bg-white/5 px-3 py-1 text-slate-300 ring-1 ring-white/10"
        chip.textContent = counts[name] > 1 ? `${name} ×${counts[name]}` : name
        return chip
      }),
    )
  }

  function renderFound(found) {
    el.foundEmpty.classList.toggle("hidden", found.length > 0)
    el.found.replaceChildren(
      ...found.map(find => {
        const row = document.createElement("li")
        row.className = "flex items-center justify-between gap-3 rounded-lg bg-white/[0.03] px-3 py-2 ring-1 ring-white/5"

        const name = document.createElement("span")
        name.className = "text-slate-200"
        name.textContent = `${find.emoji} ${find.target}`

        const detail = document.createElement("span")
        detail.className = "font-mono text-xs text-slate-400"
        detail.textContent = `${find.seconds}s · +${find.points}`

        row.append(name, detail)
        return row
      }),
    )
  }

  function celebrate(find) {
    el.celebrateEmoji.textContent = find.emoji
    el.celebrateDetail.textContent = `${find.target} in ${find.seconds}s · +${find.points} ${find.points === 1 ? "point" : "points"}`

    // Restart the CSS animation: remove the class, make the browser notice
    // (reading offsetWidth forces a layout), then add it back.
    const card = el.celebrate.firstElementChild
    card.classList.remove("celebrate-pop")
    void card.offsetWidth
    card.classList.add("celebrate-pop")

    el.celebrate.classList.replace("hidden", "grid")
    clearTimeout(celebrate.timer)
    celebrate.timer = setTimeout(() => el.celebrate.classList.replace("grid", "hidden"), 2200)

    navigator.vibrate?.(150)
  }
}

function setAll(elements, text) {
  elements.forEach(element => (element.textContent = text))
}
