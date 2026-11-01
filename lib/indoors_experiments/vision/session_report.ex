defmodule IndoorsExperiments.Vision.SessionReport do
  @moduledoc """
  Turns a recorded session folder (see `Recorder`) into:

    * a plain-text summary: device, fps, latency, tilt, what was tracked,
      and a timeline of decisions
    * `contact_sheet.jpg`: a grid of annotated snapshots across the session,
      so one image shows what happened from start to finish

  Run it with `mix vision.report` (newest session) or
  `mix vision.report tmp/sessions/<folder>`.
  """

  @contact_sheet_columns 4
  @contact_sheet_max_images 24
  @contact_sheet_tile_width 320

  @doc "Builds the report. Returns `{text, contact_sheet_path_or_nil}`."
  def build(dir) do
    session = read_json(Path.join(dir, "session.json"))
    frames = read_jsonl(Path.join(dir, "frames.jsonl"))
    events = read_jsonl(Path.join(dir, "events.jsonl"))
    sheet = write_contact_sheet(dir)

    text =
      [
        # `latest` is a symlink, so show the folder it points at.
        "Session #{dir |> Path.expand() |> real_path() |> Path.basename()}",
        device_section(session, events),
        frames_section(frames),
        latency_section(frames),
        orientation_section(frames),
        tracks_section(frames),
        decision_section(frames),
        problems_section(frames, events),
        if(sheet, do: "Contact sheet: #{sheet}", else: "Contact sheet: no snapshots yet")
      ]
      |> List.flatten()
      |> Enum.join("\n")

    {text, sheet}
  end

  # --- Sections ----------------------------------------------------------------

  defp device_section(session, events) do
    client = session["client"] || %{}
    camera = Enum.find(events, &(&1["message"] == "camera started"))

    camera_line =
      case camera do
        %{"details" => d} ->
          "  camera: #{d["width"]}x#{d["height"]} #{d["facingMode"]} \"#{d["label"]}\""

        nil ->
          "  camera: (no camera event; maybe a video file was used)"
      end

    [
      "",
      "Device",
      "  browser: #{client["user_agent"]}",
      "  screen: #{inspect(client["screen"])} @#{client["pixel_ratio"]}x, secure context: #{client["secure_context"]}",
      camera_line
    ]
  end

  defp frames_section([]), do: ["", "Frames: none recorded"]

  defp frames_section(frames) do
    seconds = duration_s(frames)
    fps = if seconds > 0, do: Float.round(length(frames) / seconds, 1), else: 0
    sent = frames |> Enum.find_value(& &1["frame"]) || %{}
    kb = frames |> Enum.map(& &1["jpeg_bytes"]) |> average() |> Kernel./(1024) |> round()

    [
      "",
      "Frames: #{length(frames)} over #{Float.round(seconds, 1)}s = #{fps} fps",
      "  sent at #{sent["width"]}x#{sent["height"]}, about #{kb} KB each"
    ]
  end

  defp latency_section(frames) do
    client = frames |> Enum.map(& &1["client"]) |> Enum.reject(&is_nil/1)
    timings = frames |> Enum.map(& &1["timings"]) |> Enum.reject(&is_nil/1)

    network =
      Enum.zip_with(Enum.drop(frames, 1), frames, fn next, this -> network_ms(next, this) end)

    [
      "",
      "Latency in ms (median / 90th percentile / max)",
      latency_line("round trip", Enum.map(client, & &1["round_trip_ms"])),
      latency_line("  network", Enum.reject(network, &is_nil/1)),
      latency_line("  server", Enum.map(frames, & &1["server_ms"])),
      latency_line("    model", Enum.map(timings, & &1["model_ms"])),
      latency_line("    preprocess", Enum.map(timings, & &1["preprocess_ms"])),
      latency_line("    decode", Enum.map(timings, & &1["decode_ms"])),
      latency_line("capture+encode", Enum.map(client, & &1["capture_ms"]))
    ]
  end

  # The browser reports frame N's round trip along with frame N+1, so line them up.
  defp network_ms(next, this) do
    with %{"round_trip_ms" => round_trip} <- next["client"],
         server when is_number(server) <- this["server_ms"] do
      max(round_trip - server, 0)
    else
      _ -> nil
    end
  end

  defp orientation_section(frames) do
    readings = frames |> Enum.map(& &1["orientation"]) |> Enum.filter(&(&1 && &1["roll"]))

    if readings == [] do
      ["", "Orientation: no sensor data (laptop, or permission not granted)"]
    else
      rolls = Enum.map(readings, &abs(&1["roll"]))
      pitches = Enum.map(readings, &abs(&1["pitch"]))
      level = Enum.count(readings, &(abs(&1["roll"]) <= 4 and abs(&1["pitch"]) <= 10))

      [
        "",
        "Orientation: #{length(readings)}/#{length(frames)} frames had data, level #{percent(level, length(readings))} of the time",
        "  |roll| avg #{round(average(rolls))}° max #{round(Enum.max(rolls))}°, |pitch| avg #{round(average(pitches))}° max #{round(Enum.max(pitches))}°"
      ]
    end
  end

  # Many short tracks for one real object means the tracker keeps losing it.
  defp tracks_section(frames) do
    appearances =
      for frame <- frames, track <- frame["tracks"] || [], do: {track["id"], track["class"]}

    if appearances == [] do
      ["", "Tracks: nothing was ever detected"]
    else
      by_track = Enum.frequencies(appearances)

      lines =
        by_track
        |> Enum.group_by(fn {{_id, class}, _frames} -> class end, fn {_, frames} -> frames end)
        |> Enum.sort_by(fn {_class, lifetimes} -> -length(lifetimes) end)
        |> Enum.map(fn {class, lifetimes} ->
          "  #{class}: #{length(lifetimes)} tracks, lasting #{round(average(lifetimes))} frames on average (longest #{Enum.max(lifetimes)})"
        end)

      max_at_once = frames |> Enum.map(&length(&1["tracks"] || [])) |> Enum.max()
      ["", "Tracks (max #{max_at_once} at once)" | lines]
    end
  end

  defp decision_section([]), do: []

  defp decision_section(frames) do
    start_t = hd(frames)["t"]
    decided = Enum.filter(frames, & &1["decision"])

    changes =
      decided
      |> Enum.chunk_by(& &1["decision"]["level"])
      |> Enum.map(fn [first | _] = run ->
        seconds = Float.round((first["t"] - start_t) / 1000, 1)

        "  #{String.pad_leading("#{seconds}s", 7)}  #{String.upcase(first["decision"]["level"])} for #{length(run)} frames: #{first["decision"]["reason"]}"
      end)

    share =
      decided
      |> Enum.frequencies_by(& &1["decision"]["level"])
      |> Enum.map_join(", ", fn {level, count} ->
        "#{String.upcase(level)} #{percent(count, length(decided))}"
      end)

    ["", "Decision timeline", Enum.take(changes, 40), "  time in each: #{share}"]
  end

  defp problems_section(frames, events) do
    errors = Enum.filter(frames, & &1["error"])

    gaps =
      frames
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b["t"] - a["t"] end)
      |> Enum.filter(&(&1 > 500))

    browser_problems =
      events
      |> Enum.filter(&(&1["level"] in ["warning", "error"]))
      |> Enum.map(&"  browser #{&1["level"]}: #{&1["message"]}")

    lines =
      [
        errors != [] &&
          "  #{length(errors)} frames failed on the server: #{errors |> Enum.map(& &1["error"]) |> Enum.uniq() |> Enum.join(", ")}",
        gaps != [] &&
          "  #{length(gaps)} pauses over 0.5s between frames (longest #{Enum.max(gaps)} ms)"
      ]
      |> Enum.filter(& &1)
      |> Kernel.++(Enum.take(browser_problems, 20))

    if lines == [], do: ["", "Problems: none"], else: ["", "Problems" | lines]
  end

  # --- Contact sheet -------------------------------------------------------------

  defp write_contact_sheet(dir) do
    case Path.wildcard(Path.join([dir, "annotated", "*.jpg"])) |> Enum.sort() do
      [] ->
        nil

      paths ->
        tiles = paths |> evenly_sample(@contact_sheet_max_images) |> Enum.map(&tile/1)
        # Black tiles fill up the last row, since every row must be the same width.
        {height, width, _} = hd(tiles).shape
        blank = Evision.Mat.from_nx_2d(Nx.broadcast(Nx.tensor(0, type: :u8), {height, width, 3}))

        rows =
          tiles
          |> Enum.chunk_every(
            @contact_sheet_columns,
            @contact_sheet_columns,
            Stream.repeatedly(fn -> blank end)
          )
          |> Enum.map(&Evision.hconcat/1)

        path = Path.join(dir, "contact_sheet.jpg")
        File.write!(path, Evision.imencode(".jpg", Evision.vconcat(rows)))
        path
    end
  end

  defp tile(path) do
    image = Evision.imread(path)
    {height, width, _} = image.shape
    tile_height = round(height * @contact_sheet_tile_width / width)
    Evision.resize(image, {@contact_sheet_tile_width, tile_height})
  end

  defp evenly_sample(list, max) when length(list) <= max, do: list

  defp evenly_sample(list, max) do
    step = (length(list) - 1) / (max - 1)
    for i <- 0..(max - 1), do: Enum.at(list, round(i * step))
  end

  # --- Helpers --------------------------------------------------------------------

  defp latency_line(label, values) do
    case Enum.filter(values, &is_number/1) |> Enum.sort() do
      [] ->
        "  #{String.pad_trailing(label, 16)} -"

      sorted ->
        "  #{String.pad_trailing(label, 16)} #{round(percentile(sorted, 0.5))} / #{round(percentile(sorted, 0.9))} / #{round(List.last(sorted))}"
    end
  end

  defp real_path(path) do
    case File.read_link(path) do
      {:ok, target} -> Path.expand(target, Path.dirname(path))
      {:error, _not_a_link} -> path
    end
  end

  defp percentile(sorted, p), do: Enum.at(sorted, round((length(sorted) - 1) * p))

  defp duration_s(frames), do: (List.last(frames)["t"] - hd(frames)["t"]) / 1000

  defp average([]), do: 0
  defp average(values), do: Enum.sum(values) / length(values)

  defp percent(_part, 0), do: "0%"
  defp percent(part, whole), do: "#{round(part / whole * 100)}%"

  defp read_json(path) do
    if File.exists?(path), do: path |> File.read!() |> Jason.decode!(), else: %{}
  end

  defp read_jsonl(path) do
    if File.exists?(path) do
      path |> File.stream!() |> Enum.map(&Jason.decode!/1)
    else
      []
    end
  end
end
