defmodule IndoorsExperiments.Vision.ZonesTest do
  use ExUnit.Case, async: true

  alias IndoorsExperiments.Vision.Zones

  test "right of centre near the bottom is my half, left is oncoming" do
    assert Zones.zone_for(0.6, 0.95) == :my_half
    assert Zones.zone_for(0.4, 0.95) == :oncoming_half
  end

  test "outside the lane or above the horizon is off path" do
    assert Zones.zone_for(0.95, 0.95) == :off_path
    assert Zones.zone_for(0.05, 0.95) == :off_path
    assert Zones.zone_for(0.5, 0.2) == :off_path
  end

  test "the lane narrows towards the horizon" do
    # 0.7 is inside the lane at the bottom, but outside it just below the horizon.
    assert Zones.zone_for(0.7, 1.0) == :my_half
    assert Zones.zone_for(0.7, 0.45) == :off_path
  end
end
