defmodule IndoorsExperiments.Vision.Tracker do
  @moduledoc """
  Stage 3 of the pipeline: **tracking**.

  The detector looks at every frame on its own. It can tell you "there is a
  person here", but not "this is the SAME person as last frame". The tracker
  adds that memory, which is what lets us measure motion over time.

  Every frame we:

    1. **Match** new detections to existing tracks by how much their boxes
       overlap (IoU). Best overlaps get paired first.
    2. **Update** matched tracks with their new box, and remember it in a short history.
    3. **Start** a new track for every detection nobody claimed.
    4. **Forget** tracks that haven't been seen for a few frames.
    5. **Measure motion** for every track from its history: how fast the box
       is growing (a growing box means the object is getting closer) and how
       fast it is moving sideways.

  This is a plain data structure, not a process. The channel process for
  each browser session holds one of these and passes it back in each frame.
  """

  alias IndoorsExperiments.Vision.Box

  # Two boxes must overlap at least this much to count as the same object.
  @min_iou_to_match 0.3

  # A track nobody matched for this many frames in a row is deleted.
  @max_missed_frames 5

  # How many past boxes each track remembers.
  @history_length 20

  # Motion is measured over (up to) the last second of history...
  @motion_window_ms 1_000
  # ...but only once we have at least this much history, otherwise one noisy
  # box can look like a huge jump.
  @min_motion_window_ms 300

  # Growing faster than this (10% of its own size per second) counts as approaching.
  @approaching_growth_per_s 0.10

  defstruct tracks: [], next_id: 1

  @doc "An empty tracker."
  def new, do: %__MODULE__{}

  @doc """
  Feed one frame's detections into the tracker.

  `detections` is a list of `%{class: "person", score: 0.9, box: box}` maps.
  `timestamp_ms` is when the frame was captured (from the browser), so
  speeds are measured in real time, not in "per frame".
  """
  def update(%__MODULE__{} = tracker, detections, timestamp_ms) do
    {pairs, unmatched_tracks, unmatched_detections} = match(tracker.tracks, detections)

    matched = Enum.map(pairs, fn {track, det} -> extend_track(track, det, timestamp_ms) end)

    still_waiting =
      unmatched_tracks
      |> Enum.map(fn track -> %{track | missed: track.missed + 1} end)
      |> Enum.filter(fn track -> track.missed <= @max_missed_frames end)

    {new_tracks, next_id} = start_tracks(unmatched_detections, tracker.next_id, timestamp_ms)

    tracks =
      (matched ++ still_waiting ++ new_tracks)
      |> Enum.map(&measure_motion/1)
      |> Enum.sort_by(& &1.id)

    %__MODULE__{tracks: tracks, next_id: next_id}
  end

  @doc "Tracks that were matched on the latest frame (the ones worth drawing)."
  def visible_tracks(%__MODULE__{tracks: tracks}), do: Enum.filter(tracks, &(&1.missed == 0))

  # --- 1. Matching -----------------------------------------------------------

  # Greedy matching: list every (track, detection) pair of the same class,
  # sort by overlap, then walk down the list taking a pair whenever neither
  # side has been taken yet.
  defp match(tracks, detections) do
    candidates =
      for track <- tracks,
          {det, det_index} <- Enum.with_index(detections),
          track.class == det.class,
          overlap = Box.iou(track.box, det.box),
          overlap >= @min_iou_to_match do
        {overlap, track, det, det_index}
      end

    {pairs, used_track_ids, used_det_indexes} =
      candidates
      |> Enum.sort_by(fn {overlap, _, _, _} -> overlap end, :desc)
      |> Enum.reduce({[], MapSet.new(), MapSet.new()}, fn {_overlap, track, det, det_index},
                                                          {pairs, used_tracks, used_dets} ->
        if MapSet.member?(used_tracks, track.id) or MapSet.member?(used_dets, det_index) do
          {pairs, used_tracks, used_dets}
        else
          {[{track, det} | pairs], MapSet.put(used_tracks, track.id),
           MapSet.put(used_dets, det_index)}
        end
      end)

    unmatched_tracks = Enum.reject(tracks, &MapSet.member?(used_track_ids, &1.id))

    unmatched_detections =
      detections
      |> Enum.with_index()
      |> Enum.reject(fn {_det, index} -> MapSet.member?(used_det_indexes, index) end)
      |> Enum.map(fn {det, _index} -> det end)

    {pairs, unmatched_tracks, unmatched_detections}
  end

  # --- 2 & 3. Updating and starting tracks -----------------------------------

  defp extend_track(track, det, timestamp_ms) do
    history = Enum.take([%{t: timestamp_ms, box: det.box} | track.history], @history_length)

    %{track | box: det.box, score: det.score, history: history, missed: 0, age: track.age + 1}
  end

  defp start_tracks(detections, first_id, timestamp_ms) do
    tracks =
      detections
      |> Enum.with_index(first_id)
      |> Enum.map(fn {det, id} ->
        %{
          id: id,
          class: det.class,
          score: det.score,
          box: det.box,
          # Newest first.
          history: [%{t: timestamp_ms, box: det.box}],
          # Frames since we last saw it (0 = seen this frame).
          missed: 0,
          # Frames we have seen it in.
          age: 1,
          growth_per_s: 0.0,
          velocity: %{x: 0.0, y: 0.0},
          approaching?: false
        }
      end)

    {tracks, first_id + length(detections)}
  end

  # --- 5. Motion -------------------------------------------------------------

  # Compare the newest box to the oldest one inside the motion window.
  defp measure_motion(track) do
    [newest | _] = track.history

    oldest =
      track.history
      |> Enum.filter(fn entry -> newest.t - entry.t <= @motion_window_ms end)
      |> List.last()

    elapsed_ms = newest.t - oldest.t

    if elapsed_ms < @min_motion_window_ms do
      %{track | growth_per_s: 0.0, velocity: %{x: 0.0, y: 0.0}, approaching?: false}
    else
      seconds = elapsed_ms / 1000

      # Growth rate: how much bigger the box got, as a fraction of its old
      # size, per second. 0.25 means "25% bigger every second".
      old_size = Box.size(oldest.box)
      new_size = Box.size(newest.box)
      growth_per_s = (new_size - old_size) / old_size / seconds

      # Velocity: how far the box's center moved, in pixels per second.
      old_center = Box.center(oldest.box)
      new_center = Box.center(newest.box)

      velocity = %{
        x: (new_center.x - old_center.x) / seconds,
        y: (new_center.y - old_center.y) / seconds
      }

      %{
        track
        | growth_per_s: growth_per_s,
          velocity: velocity,
          approaching?: growth_per_s >= @approaching_growth_per_s
      }
    end
  end
end
