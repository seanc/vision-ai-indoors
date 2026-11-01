defmodule IndoorsExperiments.Vision.Decision do
  @moduledoc """
  Stage 5 of the pipeline: **decision**. Tracks + zones in, one word out:
  `:clear`, `:caution` or `:yield`.

  It works in two steps.

  ## 1. Rules (what does THIS frame say?)

  Each tracked object that can move (a person, a pet, a bike...) is checked
  against these rules, and the most serious answer wins:

    * **YIELD**: it's in my half, it's close, and it's coming towards me.
    * **CAUTION**: it's in my half and either close or coming towards me;
      or it's in the oncoming half and coming towards me.
    * **CLEAR**: otherwise.

  There's no depth sensor, so "close" means "the box is tall compared to the
  frame", and "coming towards me" means "the box is growing" (see `Tracker`).

  ## 2. Hysteresis (should we actually change our answer?)

  Single frames are noisy: a box flickers, a person is missed for a frame.
  If we showed the raw rule result, the answer would flicker too. So we only
  switch to a new answer after it has been the rule result several frames in
  a row. Getting more cautious is quick, relaxing is slow, because a late
  "CLEAR" is much less harmful than a late "YIELD".

  The confidence score is simply: of the last few frames, what fraction
  agreed with the answer we're showing?
  """

  # Only these classes count as things we might need to yield to. A chair
  # can be detected, but it won't walk into us.
  @movers [
    "person",
    "bicycle",
    "motorcycle",
    "car",
    "bus",
    "truck",
    "cat",
    "dog",
    "horse",
    "skateboard",
    "sports ball"
  ]

  # "Close" = box at least this tall, as a fraction of the frame height.
  @close_height 0.55

  # "Coming towards me fast enough to yield" = growing at least this much per second.
  # (Merely "approaching", from the Tracker, is a lower 10%/second.)
  @yield_growth_per_s 0.20

  # Frames in a row the rules must agree before we switch answer.
  @frames_to_escalate 2
  @frames_to_relax 6

  # How many recent rule results to keep for the confidence score.
  @recent_window 10

  defstruct current: :clear,
            reason: "Nothing in the way",
            track_id: nil,
            # A different answer the rules are suggesting, and for how many frames in a row.
            pending: nil,
            pending_count: 0,
            # Newest first.
            recent: []

  def new, do: %__MODULE__{}

  @doc """
  Feed one frame's tracks (with zones) into the decision, get the updated
  decision back. `frame` is `%{width: w, height: h}`.
  """
  def update(%__MODULE__{} = state, tracks, frame) do
    raw = rule_result(tracks, frame)

    state
    |> remember(raw)
    |> maybe_switch(raw)
  end

  @doc "How much the recent frames agree with the current answer, 0.0..1.0."
  def confidence(%__MODULE__{recent: []}), do: 0.0

  def confidence(%__MODULE__{recent: recent, current: current}) do
    agreeing = Enum.count(recent, fn r -> r.level == current end)
    agreeing / length(recent)
  end

  # --- 1. Rules --------------------------------------------------------------

  @doc false
  def rule_result(tracks, frame) do
    tracks
    |> Enum.filter(fn track -> track.class in @movers end)
    |> Enum.map(fn track -> judge(track, frame) end)
    |> Enum.max_by(fn result -> severity(result.level) end, fn -> clear() end)
  end

  defp judge(track, frame) do
    close? = track.box.y2 - track.box.y1 >= @close_height * frame.height
    approaching? = track.approaching?
    fast? = track.growth_per_s >= @yield_growth_per_s
    name = "#{track.class} ##{track.id}"

    cond do
      track.zone == :my_half and close? and fast? ->
        result(:yield, "#{name} is close and coming towards you in your half", track)

      track.zone == :my_half and close? ->
        result(:caution, "#{name} is close, in your half", track)

      track.zone == :my_half and approaching? ->
        result(:caution, "#{name} is approaching in your half", track)

      track.zone == :oncoming_half and approaching? ->
        result(:caution, "#{name} is approaching in the oncoming half", track)

      true ->
        clear()
    end
  end

  defp result(level, reason, track), do: %{level: level, reason: reason, track_id: track.id}
  defp clear, do: %{level: :clear, reason: "Nothing in the way", track_id: nil}

  defp severity(:clear), do: 0
  defp severity(:caution), do: 1
  defp severity(:yield), do: 2

  # --- 2. Hysteresis ---------------------------------------------------------

  defp remember(state, raw) do
    %{state | recent: Enum.take([raw | state.recent], @recent_window)}
  end

  # The rules agree with what we're already showing: keep it, refresh the reason.
  defp maybe_switch(%{current: level} = state, %{level: level} = raw) do
    %{state | reason: raw.reason, track_id: raw.track_id, pending: nil, pending_count: 0}
  end

  # The rules want something different: count how long they've wanted it.
  defp maybe_switch(state, raw) do
    count = if state.pending == raw.level, do: state.pending_count + 1, else: 1

    needed =
      if severity(raw.level) > severity(state.current),
        do: @frames_to_escalate,
        else: @frames_to_relax

    if count >= needed do
      %{
        state
        | current: raw.level,
          reason: raw.reason,
          track_id: raw.track_id,
          pending: nil,
          pending_count: 0
      }
    else
      %{state | pending: raw.level, pending_count: count}
    end
  end
end
