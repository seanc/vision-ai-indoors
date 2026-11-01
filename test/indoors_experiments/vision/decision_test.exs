defmodule IndoorsExperiments.Vision.DecisionTest do
  use ExUnit.Case, async: true

  alias IndoorsExperiments.Vision.Decision

  @frame %{width: 640, height: 480}

  defp track(zone, opts) do
    height = Keyword.get(opts, :height, 100)

    %{
      id: 1,
      class: Keyword.get(opts, :class, "person"),
      zone: zone,
      box: %{x1: 300, y1: 480 - height, x2: 360, y2: 480},
      growth_per_s: Keyword.get(opts, :growth, 0.0),
      approaching?: Keyword.get(opts, :growth, 0.0) >= 0.10
    }
  end

  defp run(frames) do
    Enum.reduce(frames, Decision.new(), fn tracks, state ->
      Decision.update(state, tracks, @frame)
    end)
  end

  test "rules: close and fast in my half yields" do
    assert %{level: :yield} =
             Decision.rule_result([track(:my_half, height: 400, growth: 0.5)], @frame)
  end

  test "rules: approaching in the oncoming half is caution" do
    assert %{level: :caution} = Decision.rule_result([track(:oncoming_half, growth: 0.3)], @frame)
  end

  test "rules: things off the path, or that can't move, are ignored" do
    assert %{level: :clear} =
             Decision.rule_result([track(:off_path, height: 400, growth: 0.5)], @frame)

    assert %{level: :clear} =
             Decision.rule_result(
               [track(:my_half, class: "chair", height: 400, growth: 0.5)],
               @frame
             )
  end

  test "hysteresis: one bad frame doesn't change the answer" do
    danger = [track(:my_half, height: 400, growth: 0.5)]
    assert %{current: :clear} = run([danger, []])
  end

  test "hysteresis: escalates after two frames, relaxes only after six" do
    danger = [track(:my_half, height: 400, growth: 0.5)]

    assert %{current: :yield} = run([danger, danger])
    assert %{current: :yield} = run([danger, danger] ++ List.duplicate([], 5))
    assert %{current: :clear} = run([danger, danger] ++ List.duplicate([], 6))
  end
end
