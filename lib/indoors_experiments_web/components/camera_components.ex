defmodule IndoorsExperimentsWeb.CameraComponents do
  @moduledoc """
  The pieces every camera page shares: the stage (video + overlay canvas +
  focus mode), the camera controls, and the latency panel.

  The element ids here are what `assets/js/vision/session.js` looks for, so
  each page can contain these components only once.
  """

  use Phoenix.Component

  import IndoorsExperimentsWeb.CoreComponents, only: [icon: 1]

  @doc """
  The live video with the overlay canvas on top.

  Press "Focus view" and the stage fills the whole screen (`data-focus="true"`
  switches on the `data-[focus=true]:` classes below). The `hud` slot is shown
  on top of the video only in focus mode, so the important bits stay visible
  without the side panel.
  """
  slot :empty, required: true, doc: "shown before the camera starts"
  slot :hud, doc: "heads-up display, visible in focus mode only"

  def camera_stage(assigns) do
    ~H"""
    <div
      id="stage"
      data-focus="false"
      class={[
        "group relative overflow-hidden rounded-2xl bg-black shadow-2xl shadow-black/50 ring-1 ring-white/10",
        "data-[focus=true]:fixed data-[focus=true]:inset-0 data-[focus=true]:z-50",
        "data-[focus=true]:h-dvh data-[focus=true]:rounded-none data-[focus=true]:ring-0"
      ]}
    >
      <%!-- playsinline stops iOS taking the video fullscreen on its own (which would hide the overlay). --%>
      <video
        id="video"
        class="block aspect-video w-full object-contain group-data-[focus=true]:aspect-auto group-data-[focus=true]:h-full"
        playsinline
        muted
      >
      </video>
      <canvas id="overlay" class="pointer-events-none absolute inset-0 h-full w-full"></canvas>

      <div class={[
        "pointer-events-none absolute inset-x-0 top-0 hidden items-start justify-between gap-3",
        "bg-gradient-to-b from-black/70 to-transparent pb-10 group-data-[focus=true]:flex",
        "pt-[max(0.75rem,env(safe-area-inset-top))] pr-[max(0.75rem,env(safe-area-inset-right))]",
        "pl-[max(0.75rem,env(safe-area-inset-left))]"
      ]}>
        <div class="min-w-0 flex-1">{render_slot(@hud)}</div>
        <button
          id="focus-exit"
          type="button"
          data-focus-toggle
          class="pointer-events-auto grid size-11 shrink-0 place-items-center rounded-full bg-black/60 text-white ring-1 ring-white/20 backdrop-blur transition hover:bg-black/80"
          aria-label="Exit focus view"
        >
          <.icon name="hero-arrows-pointing-in" class="size-5" />
        </button>
      </div>

      <div
        id="stage-empty"
        class="absolute inset-0 grid place-items-center bg-[radial-gradient(ellipse_at_center,rgba(16,185,129,0.08),transparent_60%)]"
      >
        {render_slot(@empty)}
      </div>
    </div>
    """
  end

  @doc "Start camera / video file / stop / focus view / fps."
  def camera_controls(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <button
        id="start-camera"
        type="button"
        class="inline-flex items-center gap-2 rounded-xl bg-emerald-400 px-4 py-2.5 text-sm font-semibold text-[#06120d] shadow-lg shadow-emerald-500/20 transition hover:-translate-y-0.5 hover:bg-emerald-300 active:translate-y-0"
      >
        <.icon name="hero-video-camera-mini" class="size-4" /> Start camera
      </button>

      <label
        for="video-file"
        class="inline-flex cursor-pointer items-center gap-2 rounded-xl bg-white/5 px-4 py-2.5 text-sm font-medium text-slate-200 ring-1 ring-white/10 transition hover:-translate-y-0.5 hover:bg-white/10"
      >
        <.icon name="hero-film-mini" class="size-4" /> Video file
        <input id="video-file" type="file" accept="video/*" class="sr-only" />
      </label>

      <button
        id="focus-enter"
        type="button"
        data-focus-toggle
        class="inline-flex items-center gap-2 rounded-xl bg-white/5 px-4 py-2.5 text-sm font-medium text-slate-200 ring-1 ring-white/10 transition hover:-translate-y-0.5 hover:bg-white/10"
      >
        <.icon name="hero-arrows-pointing-out-mini" class="size-4" /> Focus view
      </button>

      <button
        id="stop"
        type="button"
        disabled
        class="inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-medium text-slate-400 ring-1 ring-white/10 transition hover:text-slate-200 disabled:cursor-not-allowed disabled:opacity-40"
      >
        <.icon name="hero-stop-mini" class="size-4" /> Stop
      </button>

      <label class="ml-auto flex items-center gap-2 text-xs text-slate-400">
        Target fps
        <select
          id="fps-select"
          class="rounded-lg border-0 bg-white/5 py-1.5 pr-8 pl-3 text-sm text-slate-200 ring-1 ring-white/10 focus:ring-emerald-400/60"
        >
          <option value="2">2</option>
          <option value="5">5</option>
          <option value="8" selected>8</option>
          <option value="12">12</option>
        </select>
      </label>
    </div>

    <%!-- Hidden: frames are drawn here to be encoded as JPEG. --%>
    <canvas id="capture-canvas" class="hidden"></canvas>
    """
  end

  @doc "The connection/status line under the controls."
  slot :inner_block, doc: "extra info on the right"

  def status_line(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p
        id="status"
        class="text-xs text-slate-500 data-[ok=false]:text-rose-300 data-[ok=true]:text-emerald-300"
      >
        Connecting…
      </p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "fps, round trip, server and model time, plus a bar showing where each frame's time goes."
  def latency_panel(assigns) do
    ~H"""
    <div class="rounded-2xl bg-white/[0.03] p-5 ring-1 ring-white/10">
      <p class="text-[11px] font-semibold tracking-[0.2em] text-slate-500 uppercase">Latency</p>
      <dl class="mt-3 grid grid-cols-3 gap-y-3 text-sm">
        <.stat id="stat-fps" label="fps" />
        <.stat id="stat-round-trip" label="round trip" />
        <.stat id="stat-server" label="server" />
        <.stat id="stat-model" label="model" />
        <.stat id="stat-size" label="frame size" />
        <.stat id="stat-frame" label="frame" />
      </dl>

      <%!-- Widths are set by renderTimeline() in session.js. --%>
      <div id="latency-bar" class="mt-4 flex h-2 overflow-hidden rounded-full bg-white/5">
        <span
          :for={{segment, colour} <- latency_segments()}
          data-segment={segment}
          class={["h-full w-0 transition-[width] duration-300", colour]}
        >
        </span>
      </div>
      <ul class="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-slate-500">
        <li :for={{segment, colour} <- latency_segments()} class="flex items-center gap-1">
          <span class={["size-2 rounded-full", colour]}></span>{segment}
        </li>
      </ul>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="flex flex-col-reverse">
      <dt class="text-[11px] text-slate-500">{@label}</dt>
      <dd id={@id} class="font-mono text-base font-semibold text-slate-100 tabular-nums">–</dd>
    </div>
    """
  end

  # Segments of the latency bar, in the order a frame goes through them.
  defp latency_segments do
    [
      {"capture", "bg-sky-400"},
      {"network", "bg-slate-400"},
      {"preprocess", "bg-violet-400"},
      {"model", "bg-emerald-400"},
      {"decode", "bg-amber-400"},
      {"track", "bg-rose-400"}
    ]
  end
end
