defmodule IndoorsExperiments.Vision.Zones do
  @moduledoc """
  Stage 4 of the pipeline: **path understanding** (the indoor stand-in).

  On the bike this stage will be a segmentation model that finds the real
  path and splits it into "my half" and "the oncoming half". We don't have
  that model yet, so indoors we *draw* the path by hand: a fixed trapezoid
  that narrows towards the horizon, like a hallway or a trail seen from
  chest height.

                      horizon (40% down, same as the capture guide)
                             ____|____
                            /    |    \\
                           /     |     \\
           oncoming half  /      |      \\  my half
                         /       |       \\
                        /________|________\\
                               bottom

  Riding on the right, the right half is "mine". Anything standing outside
  the trapezoid (or above the horizon) is `:off_path`.

  To decide where an object is, we look at the middle of its box's bottom
  edge, which is roughly where it touches the floor.

  When the real path model exists, only `zone_for/3` needs to change: look
  the point up in the predicted mask instead of in this trapezoid.
  """

  alias IndoorsExperiments.Vision.Box

  # All positions are fractions of the frame (0.0 = left/top, 1.0 = right/bottom),
  # so the same lane works for any camera resolution.
  @horizon_y 0.40
  @center_x 0.50
  # Half the lane's width at the bottom of the frame and at the horizon.
  @half_width_at_bottom 0.35
  @half_width_at_horizon 0.04

  @doc "Adds a `:zone` to every track for this frame."
  def assign(tracks, frame) do
    Enum.map(tracks, fn track ->
      %{x: x, y: y} = Box.bottom_center(track.box)
      zone = zone_for(x / frame.width, y / frame.height)
      Map.put(track, :zone, zone)
    end)
  end

  @doc """
  Which zone is the point (x, y)? Both are fractions of the frame size.
  Returns `:my_half`, `:oncoming_half`, or `:off_path`.
  """
  def zone_for(_x, y) when y < @horizon_y, do: :off_path

  def zone_for(x, y) do
    # How far down from the horizon is this point? 0.0 at the horizon, 1.0 at the bottom.
    depth = (y - @horizon_y) / (1.0 - @horizon_y)

    # The lane gets wider the closer it is to us (the further down the frame).
    half_width = @half_width_at_horizon + depth * (@half_width_at_bottom - @half_width_at_horizon)

    cond do
      x < @center_x - half_width -> :off_path
      x > @center_x + half_width -> :off_path
      x >= @center_x -> :my_half
      true -> :oncoming_half
    end
  end

  @doc """
  The lane outline for the browser to draw, so the overlay always matches
  the zones the server actually uses. Points are fractions of the frame size.
  """
  def lane_outline do
    %{
      horizon_y: @horizon_y,
      center_x: @center_x,
      polygon: [
        [@center_x - @half_width_at_horizon, @horizon_y],
        [@center_x + @half_width_at_horizon, @horizon_y],
        [@center_x + @half_width_at_bottom, 1.0],
        [@center_x - @half_width_at_bottom, 1.0]
      ]
    }
  end
end
