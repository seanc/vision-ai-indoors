defmodule IndoorsExperiments.Vision.TrackerTest do
  use ExUnit.Case, async: true

  alias IndoorsExperiments.Vision.Tracker

  defp person(x1, y1, x2, y2),
    do: %{class: "person", score: 0.9, box: %{x1: x1, y1: y1, x2: x2, y2: y2}}

  test "the same object keeps its id across frames" do
    tracker =
      Tracker.new()
      |> Tracker.update([person(100, 100, 200, 300)], 0)
      |> Tracker.update([person(105, 100, 205, 300)], 100)

    assert [%{id: 1, age: 2}] = tracker.tracks
  end

  test "objects that don't overlap get separate ids" do
    tracker = Tracker.update(Tracker.new(), [person(0, 0, 50, 50), person(300, 300, 350, 350)], 0)
    assert Enum.map(tracker.tracks, & &1.id) == [1, 2]
  end

  test "a box growing steadily is marked approaching" do
    tracker =
      Enum.reduce(0..5, Tracker.new(), fn step, tracker ->
        grow = step * 10

        Tracker.update(
          tracker,
          [person(200 - grow, 200 - grow, 300 + grow, 400 + grow)],
          step * 100
        )
      end)

    assert [%{approaching?: true, growth_per_s: growth}] = tracker.tracks
    assert growth > 0.5
  end

  test "a box that stays the same size is not approaching" do
    tracker =
      Enum.reduce(0..5, Tracker.new(), fn step, tracker ->
        Tracker.update(tracker, [person(200, 200, 300, 400)], step * 100)
      end)

    assert [%{approaching?: false}] = tracker.tracks
  end

  test "a track survives a few missed frames, then is forgotten" do
    tracker = Tracker.update(Tracker.new(), [person(0, 0, 50, 50)], 0)

    after_three = Enum.reduce(1..3, tracker, &Tracker.update(&2, [], &1 * 100))
    assert [%{missed: 3}] = after_three.tracks
    assert Tracker.visible_tracks(after_three) == []

    after_six = Enum.reduce(4..6, after_three, &Tracker.update(&2, [], &1 * 100))
    assert after_six.tracks == []
  end
end
