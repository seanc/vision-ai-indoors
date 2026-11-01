defmodule IndoorsExperiments.Vision.HuntPipeline do
  @moduledoc """
  The scavenger hunt's pipeline. Compare it with `Pipeline` (the hallway
  one): the first stages are identical, only the end is swapped.

      capture  ->  perception  ->  tracking  ->  game rules
      (browser)    Detector        Tracker       Hunt

  Like `Pipeline`, this struct is the session's memory and lives in the
  channel process for one browser tab (`IndoorsExperimentsWeb.HuntChannel`).
  """

  alias IndoorsExperiments.Vision.{Detector, Hunt, Tracker}

  defstruct [:hunt, tracker: Tracker.new(), frames: 0]

  @doc "A new game. `opts` go to `Hunt.new/2` (e.g. `target: \"cup\"`)."
  def new(now, opts \\ []), do: %__MODULE__{hunt: Hunt.new(now, opts)}

  @doc "Runs one frame through every stage. Returns `{result, new_pipeline}`."
  def process(%__MODULE__{} = pipeline, jpeg, meta) do
    case Detector.detect(jpeg) do
      {:ok, %{detections: detections, frame: frame, timings: timings}} ->
        tracker = Tracker.update(pipeline.tracker, detections, meta["t"])
        tracks = Tracker.visible_tracks(tracker)
        hunt = Hunt.update(pipeline.hunt, tracks, meta["t"])

        pipeline = %{pipeline | tracker: tracker, hunt: hunt, frames: pipeline.frames + 1}
        {result(pipeline, tracks, frame, timings, meta["t"]), pipeline}

      {:error, reason} ->
        {%{error: to_string(reason), frame_number: pipeline.frames}, pipeline}
    end
  end

  @doc "The player gave up on this target."
  def skip(%__MODULE__{} = pipeline, now), do: %{pipeline | hunt: Hunt.skip(pipeline.hunt, now)}

  @doc "Just the game state, for replies that don't come with a frame (like skip)."
  def summary(%__MODULE__{hunt: hunt}, now) do
    %{
      phase: hunt.phase,
      target: hunt.target,
      seconds_hunting: Float.round(max(now - hunt.target_started_at, 0) / 1000, 1),
      lock: Float.round(hunt.lock, 2),
      frames_to_lock: Hunt.frames_to_lock(),
      locked_track_id: hunt.locked_track_id,
      score: hunt.score,
      found: Enum.take(hunt.found, 8),
      found_count: length(hunt.found),
      skipped: hunt.skipped
    }
  end

  defp result(pipeline, tracks, frame, timings, now) do
    target = pipeline.hunt.target.class

    %{
      frame_number: pipeline.frames,
      frame: frame,
      timings: timings,
      tracks:
        Enum.map(tracks, fn track ->
          %{
            id: track.id,
            class: track.class,
            score: Float.round(track.score, 2),
            box: track.box,
            age: track.age,
            target: track.class == target
          }
        end),
      hunt: summary(pipeline, now)
    }
  end
end
