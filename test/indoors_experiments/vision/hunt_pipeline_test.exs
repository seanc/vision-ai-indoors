defmodule IndoorsExperiments.Vision.HuntPipelineTest do
  use ExUnit.Case, async: true

  import IndoorsExperiments.VisionFixtures

  alias IndoorsExperiments.Vision.HuntPipeline

  test "holding the camera on the target for a few frames finds it" do
    jpeg = jpeg("bus.jpg")

    results =
      Enum.map_reduce(0..4, HuntPipeline.new(0, target: "bus"), fn i, pipeline ->
        HuntPipeline.process(pipeline, jpeg, %{"t" => i * 125})
      end)
      |> elem(0)

    phases = Enum.map(results, & &1.hunt.phase)
    assert List.first(phases) == :hunting
    assert List.last(phases) == :found

    last = List.last(results)
    assert last.hunt.score == 1
    assert Enum.any?(last.tracks, &(&1.class == "bus" and &1.target))
    assert Enum.any?(last.tracks, &(&1.class == "person" and not &1.target))
  end
end
