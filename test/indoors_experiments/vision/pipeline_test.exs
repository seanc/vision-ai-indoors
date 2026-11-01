defmodule IndoorsExperiments.Vision.PipelineTest do
  use ExUnit.Case, async: true

  import IndoorsExperiments.VisionFixtures

  alias IndoorsExperiments.Vision.Pipeline

  test "someone 'walking towards the camera' in my half goes CLEAR -> CAUTION -> YIELD" do
    # 12 frames at 8 fps = 1.5 seconds of zooming into the photo.
    results =
      approaching_frames(12, 1.5)
      |> Enum.with_index()
      |> Enum.map_reduce(Pipeline.new(), fn {jpeg, i}, pipeline ->
        Pipeline.process(pipeline, jpeg, %{"t" => i * 125})
      end)
      |> elem(0)

    levels = results |> Enum.map(& &1.decision.level) |> Enum.dedup()
    assert levels == [:clear, :caution, :yield]

    last = List.last(results)
    cause = Enum.find(last.tracks, &(&1.id == last.decision.track_id))
    assert %{class: "person", zone: :my_half, approaching: true} = cause
  end
end
