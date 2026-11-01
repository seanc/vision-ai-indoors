defmodule IndoorsExperiments.Vision.Hunt do
  @moduledoc """
  The scavenger hunt's rules. This replaces the bike pipeline's last two
  stages (zones + decision): same detector, same tracker, different question.

  The game names an object ("find a cup"). You walk around with the camera
  until the tracker has followed a cup across several frames, then you
  score and get the next target.

  ## Why "several frames" and not just "the detector saw a cup"?

  Detectors make one-frame mistakes all the time: a dark mug becomes a
  "bowl" for a frame, a remote becomes a "cell phone". Requiring the *same
  tracked object* to be seen in 4 frames, with decent confidence, means a
  single lucky frame doesn't count. That's the tracker doing for the game
  what hysteresis does for the bike decision.

  ## Phases

      :hunting  -- looking for the target
      :found    -- celebrating for a couple of seconds, then a new target

  All times are the browser's capture timestamps in milliseconds, like
  everywhere else in the pipeline.
  """

  # A track must have been seen in this many frames to count as found...
  @frames_to_lock 4
  # ...and be at least this confident on the frame it's found.
  @min_score 0.5
  # How long the "found it!" screen stays up before the next target.
  @celebrate_ms 2_500
  # Don't repeat any of the last few targets.
  @no_repeat 5

  # {COCO class, emoji, points}. Objects COCO often mixes up with each other
  # indoors are left out on purpose (remote vs cell phone, cup vs vase vs bowl,
  # tv vs laptop, couch vs chair vs bed), so the game doesn't feel unfair.
  # People are left out because you'd find one instantly.
  @targets [
    {"cup", "☕", 1},
    {"bottle", "🍾", 1},
    {"book", "📖", 1},
    {"chair", "🪑", 1},
    {"laptop", "💻", 1},
    {"keyboard", "⌨️", 1},
    {"cell phone", "📱", 1},
    {"potted plant", "🪴", 2},
    {"mouse", "🖱️", 2},
    {"clock", "🕰️", 2},
    {"backpack", "🎒", 2},
    {"sink", "🚰", 2},
    {"refrigerator", "🧊", 2},
    {"microwave", "📡", 2},
    {"scissors", "✂️", 3},
    {"teddy bear", "🧸", 3},
    {"toothbrush", "🪥", 3},
    {"umbrella", "☂️", 3},
    {"banana", "🍌", 3},
    {"apple", "🍎", 3},
    {"orange", "🍊", 3},
    {"wine glass", "🍷", 3},
    {"handbag", "👜", 3}
  ]

  defstruct target: nil,
            target_started_at: nil,
            phase: :hunting,
            phase_ends_at: nil,
            # The track being "locked on" to this frame, and how far along it is (0.0..1.0).
            locked_track_id: nil,
            lock: 0.0,
            score: 0,
            # Newest first: %{target, emoji, points, seconds}
            found: [],
            skipped: 0,
            recent_targets: []

  @doc """
  A new game starting at `now` (ms). Pass `target: "cup"` to choose the
  first target instead of picking at random (used by tests).
  """
  def new(now, opts \\ []) do
    target = opts |> Keyword.get(:target) |> target_info() || random_target([])
    start_target(%__MODULE__{}, target, now)
  end

  @doc "How many frames a track must be seen in to count as found."
  def frames_to_lock, do: @frames_to_lock

  @doc "All targets, for showing on the page."
  def targets,
    do:
      Enum.map(@targets, fn {class, emoji, points} ->
        %{class: class, emoji: emoji, points: points}
      end)

  @doc "One frame's tracks in, updated game out."
  def update(%__MODULE__{phase: :found} = hunt, _tracks, now) do
    if now >= hunt.phase_ends_at, do: next_target(hunt, now), else: hunt
  end

  def update(%__MODULE__{phase: :hunting} = hunt, tracks, now) do
    case best_candidate(tracks, hunt.target.class) do
      nil ->
        %{hunt | locked_track_id: nil, lock: 0.0}

      track ->
        lock = min(track.age / @frames_to_lock, 1.0)

        if lock >= 1.0 and track.score >= @min_score do
          found(hunt, track, now)
        else
          %{hunt | locked_track_id: track.id, lock: lock}
        end
    end
  end

  @doc "Give up on the current target (no points)."
  def skip(%__MODULE__{} = hunt, now) do
    %{next_target(hunt, now) | skipped: hunt.skipped + 1}
  end

  # The target-class track the tracker has followed for longest (and that is
  # visible right now).
  defp best_candidate(tracks, class) do
    tracks
    |> Enum.filter(fn track -> track.class == class and track.missed == 0 end)
    |> Enum.max_by(fn track -> track.age end, fn -> nil end)
  end

  defp found(hunt, track, now) do
    find = %{
      target: hunt.target.class,
      emoji: hunt.target.emoji,
      points: hunt.target.points,
      seconds: Float.round((now - hunt.target_started_at) / 1000, 1)
    }

    %{
      hunt
      | phase: :found,
        phase_ends_at: now + @celebrate_ms,
        locked_track_id: track.id,
        lock: 1.0,
        score: hunt.score + hunt.target.points,
        found: [find | hunt.found]
    }
  end

  defp next_target(hunt, now) do
    start_target(hunt, random_target(hunt.recent_targets), now)
  end

  defp start_target(hunt, target, now) do
    %{
      hunt
      | target: target,
        target_started_at: now,
        phase: :hunting,
        phase_ends_at: nil,
        locked_track_id: nil,
        lock: 0.0,
        recent_targets: Enum.take([target.class | hunt.recent_targets], @no_repeat)
    }
  end

  defp random_target(recent) do
    @targets
    |> Enum.reject(fn {class, _, _} -> class in recent end)
    |> Enum.random()
    |> then(fn {class, emoji, points} -> %{class: class, emoji: emoji, points: points} end)
  end

  defp target_info(nil), do: nil

  defp target_info(class) do
    case List.keyfind(@targets, class, 0) do
      {class, emoji, points} -> %{class: class, emoji: emoji, points: points}
      # Not in the list (e.g. "bus" in a test): allow it, worth 1 point.
      nil -> %{class: class, emoji: "🔎", points: 1}
    end
  end
end
