defmodule IndoorsExperiments.Vision.BoxTest do
  use ExUnit.Case, async: true

  alias IndoorsExperiments.Vision.Box

  @box %{x1: 0, y1: 0, x2: 10, y2: 10}

  test "iou is 1.0 for identical boxes and 0.0 for separate ones" do
    assert Box.iou(@box, @box) == 1.0
    assert Box.iou(@box, %{x1: 20, y1: 20, x2: 30, y2: 30}) == 0.0
  end

  test "iou of two half-overlapping boxes" do
    # Shared area 50, combined area 100 + 100 - 50 = 150.
    assert_in_delta Box.iou(@box, %{x1: 5, y1: 0, x2: 15, y2: 10}), 50 / 150, 1.0e-9
  end

  test "size doubles when width and height double" do
    assert Box.size(%{x1: 0, y1: 0, x2: 20, y2: 20}) == 2 * Box.size(@box)
  end
end
