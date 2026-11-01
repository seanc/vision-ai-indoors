defmodule IndoorsExperiments.Vision.Recorder do
  @moduledoc """
  Writes down everything that happens in a camera session, so you can look
  at it afterwards instead of having to watch the phone screen live.

  Each session gets a folder under `tmp/sessions/` (and `tmp/sessions/latest`
  always points at the newest one):

      tmp/sessions/20261031-193012-3f9a1c/
        session.json      who connected: browser, screen size, the lane used
        frames.jsonl      one line of JSON per frame: metadata, tracks, decision, timings
        events.jsonl      things the browser reported: errors, camera info, status messages
        latest.jpg        the most recent annotated snapshot (refreshes about once a second)
        snapshots/        raw frames, about one per second. These double as a dataset.
        annotated/        the same frames with the overlay drawn on (see `Annotate`)

  Snapshots are taken about once a second, and also at interesting moments:
  whenever the hallway decision changes, or the hunt finds something or
  moves to a new target.

  Run `mix vision.report` to turn a session folder into a readable summary
  plus a contact sheet image.

  Recording is switched on by `config :indoors_experiments, :recordings_dir`.
  When that's nil (as in tests), `start/2` returns nil and every other
  function does nothing.
  """

  alias IndoorsExperiments.Vision.Annotate

  @snapshot_every_ms 1_000

  defstruct [:root, :dir, :session_info, :lane, last_snapshot_t: nil, last_moment: nil]

  @doc """
  Returns a recorder, or nil if recording is off.

  The folder isn't created until there's something to write, so opening the
  page without starting the camera doesn't leave an empty session behind.
  """
  def start(session_info, lane) do
    case Application.get_env(:indoors_experiments, :recordings_dir) do
      nil -> nil
      root -> %__MODULE__{root: Path.expand(root), session_info: session_info, lane: lane}
    end
  end

  @doc "Records one processed frame. Returns the updated recorder."
  def record_frame(nil, _jpeg, _meta, _result), do: nil

  def record_frame(%__MODULE__{} = recorder, jpeg, meta, result) do
    recorder = ensure_folder(recorder)
    append_line(recorder, "frames.jsonl", frame_line(meta, result, byte_size(jpeg)))

    moment = moment(result)

    if snapshot_due?(recorder, meta["t"], moment) do
      save_snapshot(recorder, jpeg, meta, result)
      %{recorder | last_snapshot_t: meta["t"], last_moment: moment}
    else
      %{recorder | last_moment: moment}
    end
  end

  @doc """
  Records something the browser told us about (an error, camera details...).
  Returns the updated recorder.
  """
  def record_event(nil, _event), do: nil

  def record_event(%__MODULE__{} = recorder, event) do
    recorder = ensure_folder(recorder)
    append_line(recorder, "events.jsonl", Map.put(event, "server_time", DateTime.utc_now()))
    recorder
  end

  # --- Internals -------------------------------------------------------------

  # The first time anything is recorded: create the folder and write session.json.
  defp ensure_folder(%__MODULE__{dir: nil} = recorder) do
    dir = Path.join(recorder.root, folder_name())
    File.mkdir_p!(Path.join(dir, "snapshots"))
    File.mkdir_p!(Path.join(dir, "annotated"))
    point_latest_at(recorder.root, dir)

    session =
      Map.merge(recorder.session_info, %{started_at: DateTime.utc_now(), lane: recorder.lane})

    File.write!(Path.join(dir, "session.json"), Jason.encode_to_iodata!(session, pretty: true))

    %{recorder | dir: dir}
  end

  defp ensure_folder(recorder), do: recorder

  defp folder_name do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    "#{timestamp}-#{Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)}"
  end

  # `tmp/sessions/latest` is a symlink to the newest session folder.
  defp point_latest_at(root, dir) do
    link = Path.join(root, "latest")
    File.rm(link)
    File.ln_s(Path.basename(dir), link)
  end

  # A snapshot is taken whenever this changes.
  defp moment(%{decision: decision}), do: decision.level
  defp moment(%{hunt: hunt}), do: {hunt.phase, hunt.target.class}
  defp moment(_error), do: :error

  defp snapshot_due?(%{last_snapshot_t: nil}, _t, _moment), do: true
  defp snapshot_due?(%{last_moment: previous}, _t, moment) when previous != moment, do: true
  defp snapshot_due?(%{last_snapshot_t: last}, t, _moment), do: t - last >= @snapshot_every_ms

  # Drawing and saving images takes a few milliseconds, so do it in a separate
  # process: the channel can reply to the browser straight away.
  defp save_snapshot(recorder, jpeg, meta, result) do
    name = "#{String.pad_leading(to_string(meta["seq"]), 6, "0")}.jpg"

    Task.start(fn ->
      annotated = Annotate.draw(jpeg, result, meta, recorder.lane)
      File.write!(Path.join([recorder.dir, "snapshots", name]), jpeg)
      File.write!(Path.join([recorder.dir, "annotated", name]), annotated)
      File.write!(Path.join(recorder.dir, "latest.jpg"), annotated)
    end)
  end

  defp frame_line(meta, result, jpeg_bytes) do
    %{
      seq: meta["seq"],
      t: meta["t"],
      jpeg_bytes: jpeg_bytes,
      orientation: meta["orientation"],
      # The browser measures these for the PREVIOUS frame and sends them along.
      client: meta["client"],
      server_ms: result[:server_ms],
      timings: result[:timings],
      frame: result[:frame],
      error: result[:error],
      decision: result[:decision],
      hunt: result[:hunt],
      tracks: result[:tracks]
    }
  end

  defp append_line(recorder, file, map) do
    File.write!(Path.join(recorder.dir, file), [Jason.encode_to_iodata!(map), "\n"], [:append])
  end
end
