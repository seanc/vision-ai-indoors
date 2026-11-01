defmodule IndoorsExperiments.Vision.DetectorTest do
  use ExUnit.Case, async: true

  import IndoorsExperiments.VisionFixtures

  alias IndoorsExperiments.Vision.Detector

  test "finds the bus and the people in bus.jpg" do
    {:ok, result} = Detector.detect(jpeg("bus.jpg"))

    assert result.frame == %{width: 810, height: 1080}
    classes = Enum.map(result.detections, & &1.class)
    assert "bus" in classes
    assert Enum.count(classes, &(&1 == "person")) >= 3
  end

  test "boxes are in the original image's pixels, not the 640x640 model input" do
    {:ok, result} = Detector.detect(jpeg("bus.jpg"))
    bus = Enum.find(result.detections, &(&1.class == "bus"))

    # The bus spans almost the full 810px width of the photo.
    assert bus.box.x2 - bus.box.x1 > 700
  end

  test "rejects bytes that aren't a JPEG" do
    assert {:error, :bad_jpeg} = Detector.detect("not a jpeg")
  end
end
