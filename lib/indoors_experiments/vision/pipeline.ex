defmodule IndoorsExperiments.Vision.Pipeline do
  @moduledoc """
  The whole pipeline for one camera session, in order:

      capture  ->  perception  ->  tracking  ->  path understanding  ->  decision
      (browser)    Detector        Tracker       Zones                   Decision

  Capture happens in the browser (`assets/js/vision/`). Everything else
  happens here, once per frame, in `process/3`.

  This struct is the session's memory: the tracker's tracks and the
  decision's recent history. It lives inside the channel process for that
  browser tab (see `IndoorsExperimentsWeb.VisionChannel`), so every tab gets
  its own tracks, and closing the tab throws them away.
  """

  alias IndoorsExperiments.Vision.{Decision, Detector, Tracker, Zones}

  defstruct tracker: Tracker.new(), decision: Decision.new(), frames: 0

  def new, do: %__MODULE__{}

  @doc """
  Runs one frame through every stage.

  `meta` comes from the browser: `%{"t" => capture_time_ms, ...}`.
  Returns `{result, new_pipeline}`, where `result` is a JSON-friendly map
  for the browser to draw.
  """
  def process(%__MODULE__{} = pipeline, jpeg, meta) do
    timestamp = meta["t"]

    case Detector.detect(jpeg) do
      {:ok, %{detections: detections, frame: frame, timings: timings}} ->
        tracker = Tracker.update(pipeline.tracker, detections, timestamp)
        tracks = tracker |> Tracker.visible_tracks() |> Zones.assign(frame)
        decision = Decision.update(pipeline.decision, tracks, frame)

        pipeline = %{pipeline | tracker: tracker, decision: decision, frames: pipeline.frames + 1}
        {result(pipeline, tracks, frame, timings), pipeline}

      {:error, reason} ->
        {%{error: to_string(reason), frame_number: pipeline.frames}, pipeline}
    end
  end

  # Everything the browser needs to draw the overlay. Plain maps, lists and
  # strings only, so it turns straight into JSON.
  defp result(pipeline, tracks, frame, timings) do
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
            zone: track.zone,
            growth_per_s: Float.round(track.growth_per_s, 2),
            approaching: track.approaching?
          }
        end),
      decision: %{
        level: pipeline.decision.current,
        reason: pipeline.decision.reason,
        track_id: pipeline.decision.track_id,
        confidence: Float.round(Decision.confidence(pipeline.decision), 2)
      }
    }
  end
end
