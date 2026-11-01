defmodule IndoorsExperiments.Vision.Annotate do
  @moduledoc """
  Draws the pipeline's results onto a frame **on the server**, the same way
  `assets/js/vision/overlay.js` draws them in the browser.

  The browser overlay only exists on the screen in front of you. These
  images get saved by `Recorder`, so afterwards anyone (including an AI
  assistant that can't see your phone) can look at what the pipeline
  saw and decided, frame by frame.

  On top of the overlay, each image gets two text bars:

    * top: the hallway decision (confidence and reason), or the hunt's
      target, lock-on and score
    * bottom: frame number, timings and phone tilt

  It handles results from both experiments: hallway tracks have a `:zone`,
  hunt tracks have a `:target` flag, and only the hallway has a lane.
  """

  # Evision colours are {blue, green, red}, not RGB.
  @zone_colours %{
    my_half: {153, 211, 52},
    oncoming_half: {36, 191, 251},
    off_path: {184, 163, 148}
  }

  @decision_colours %{
    clear: {120, 200, 40},
    caution: {36, 191, 251},
    yield: {94, 63, 244}
  }

  @hunt_colours %{target: {36, 191, 251}, found: {153, 211, 52}, other: {200, 200, 200}}

  @font Evision.Constant.cv_FONT_HERSHEY_SIMPLEX()

  @doc """
  Returns a new JPEG with the overlay drawn on it. `result` is the map
  `Pipeline.process/3` (or `HuntPipeline.process/3`) returns, `meta` is the
  frame's metadata from the browser, `lane` is the hallway lane (nil for the hunt).
  """
  def draw(jpeg, result, meta, lane) do
    image = Evision.imdecode(jpeg, Evision.Constant.cv_IMREAD_COLOR())
    {height, width, _} = image.shape

    image
    |> draw_lane(lane, width, height)
    |> draw_tracks(result[:tracks] || [], result)
    |> draw_top_bar(result, width)
    |> draw_bottom_bar(result, meta, width, height)
    |> then(&Evision.imencode(".jpg", &1))
  end

  # The trapezoid from Zones, with a centre line. Outlines only, so the
  # picture underneath stays visible.
  defp draw_lane(image, nil, _width, _height), do: image

  defp draw_lane(image, lane, width, height) do
    to_pixels = fn [x, y] -> {round(x * width), round(y * height)} end
    [top_left, top_right, bottom_right, bottom_left] = Enum.map(lane.polygon, to_pixels)
    top_center = to_pixels.([lane.center_x, lane.horizon_y])
    bottom_center = to_pixels.([lane.center_x, 1.0])
    horizon_y = round(lane.horizon_y * height)

    image
    |> Evision.line({0, horizon_y}, {width, horizon_y}, {255, 255, 255}, thickness: 1)
    |> Evision.line(top_left, bottom_left, @zone_colours.oncoming_half, thickness: 2)
    |> Evision.line(top_right, bottom_right, @zone_colours.my_half, thickness: 2)
    |> Evision.line(top_left, top_right, {255, 255, 255}, thickness: 1)
    |> Evision.line(top_center, bottom_center, {255, 255, 255}, thickness: 1)
  end

  defp draw_tracks(image, tracks, result) do
    Enum.reduce(tracks, image, fn track, image ->
      box = track.box
      {colour, thickness, label} = track_style(track, result)
      top_left = {round(box.x1), round(box.y1)}
      foot = {round((box.x1 + box.x2) / 2), round(box.y2)}

      image
      |> Evision.rectangle(top_left, {round(box.x2), round(box.y2)}, colour, thickness: thickness)
      |> Evision.circle(foot, 5, colour, thickness: -1)
      # (46px keeps the label below the decision bar at the top.)
      |> label(label, {round(box.x1), max(round(box.y1), 46)}, colour)
    end)
  end

  # Hallway track: coloured by zone, thick if it caused the decision.
  defp track_style(%{zone: zone} = track, result) do
    colour = Map.get(@zone_colours, zone, @zone_colours.off_path)
    thickness = if track.id == result.decision.track_id, do: 4, else: 2

    label =
      "#{track.class} ##{track.id} #{round(track.score * 100)}% " <>
        "#{signed_percent(track.growth_per_s)}/s"

    {colour, thickness, label}
  end

  # Hunt track: amber if it's the target class, green once found, grey otherwise.
  defp track_style(%{target: true} = track, %{hunt: hunt}) do
    found? = hunt.phase == :found and track.id == hunt.locked_track_id
    colour = if found?, do: @hunt_colours.found, else: @hunt_colours.target
    label = "#{track.class} ##{track.id} #{round(track.score * 100)}% seen #{track.age}x"
    {colour, 4, label}
  end

  defp track_style(track, _result) do
    {@hunt_colours.other, 1, "#{track.class} #{round(track.score * 100)}%"}
  end

  defp draw_top_bar(image, %{decision: decision}, width) do
    colour = Map.fetch!(@decision_colours, decision.level)

    text =
      "#{decision.level |> to_string() |> String.upcase()} #{round(decision.confidence * 100)}%  #{decision.reason}"

    image
    |> Evision.rectangle({0, 0}, {width, 24}, colour, thickness: -1)
    |> Evision.putText(text, {6, 17}, @font, 0.5, {20, 20, 20}, thickness: 1)
  end

  defp draw_top_bar(image, %{hunt: hunt}, width) do
    {colour, status} =
      if hunt.phase == :found,
        do: {@hunt_colours.found, "FOUND"},
        else: {@hunt_colours.target, "lock #{round(hunt.lock * 100)}%"}

    text =
      "FIND #{hunt.target.class}  #{status}  #{hunt.seconds_hunting}s  score #{hunt.score}"

    image
    |> Evision.rectangle({0, 0}, {width, 24}, colour, thickness: -1)
    |> Evision.putText(text, {6, 17}, @font, 0.5, {20, 20, 20}, thickness: 1)
  end

  defp draw_top_bar(image, result, width) do
    image
    |> Evision.rectangle({0, 0}, {width, 24}, {60, 60, 60}, thickness: -1)
    |> Evision.putText("ERROR #{result[:error]}", {6, 17}, @font, 0.5, {255, 255, 255},
      thickness: 1
    )
  end

  defp draw_bottom_bar(image, result, meta, width, height) do
    timings = result[:timings] || %{}
    orientation = meta["orientation"]

    tilt =
      if orientation && orientation["roll"],
        do: "roll #{round(orientation["roll"])} pitch #{round(orientation["pitch"])}",
        else: "no tilt sensor"

    text =
      "frame #{result[:frame_number]}  seq #{meta["seq"]}  server #{result[:server_ms]}ms  " <>
        "model #{timings[:model_ms]}ms  #{tilt}"

    image
    |> Evision.rectangle({0, height - 20}, {width, height}, {20, 20, 20}, thickness: -1)
    |> Evision.putText(text, {6, height - 6}, @font, 0.4, {230, 230, 230}, thickness: 1)
  end

  # A filled label above a box.
  defp label(image, text, {x, y}, colour) do
    {{text_w, text_h}, _baseline} = Evision.getTextSize(text, @font, 0.45, 1)

    image
    |> Evision.rectangle({x, y - text_h - 8}, {x + text_w + 8, y}, colour, thickness: -1)
    |> Evision.putText(text, {x + 4, y - 5}, @font, 0.45, {20, 20, 20}, thickness: 1)
  end

  defp signed_percent(rate) do
    percent = round(rate * 100)
    if percent >= 0, do: "+#{percent}%", else: "#{percent}%"
  end
end
