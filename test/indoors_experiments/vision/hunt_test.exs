defmodule IndoorsExperiments.Vision.HuntTest do
  use ExUnit.Case, async: true

  alias IndoorsExperiments.Vision.Hunt

  defp track(class, opts) do
    %{
      id: Keyword.get(opts, :id, 1),
      class: class,
      score: Keyword.get(opts, :score, 0.8),
      age: Keyword.get(opts, :age, 1),
      missed: 0,
      box: %{x1: 0, y1: 0, x2: 10, y2: 10}
    }
  end

  test "a target seen in enough frames is found and scores" do
    hunt = Hunt.new(0, target: "cup")

    hunt = Hunt.update(hunt, [track("cup", age: 2)], 100)
    assert %{phase: :hunting, lock: 0.5, locked_track_id: 1} = hunt

    hunt = Hunt.update(hunt, [track("cup", age: 4)], 200)
    assert %{phase: :found, score: 1, found: [%{target: "cup", seconds: 0.2}]} = hunt
  end

  test "a low-confidence sighting doesn't count, even after many frames" do
    hunt = Hunt.update(Hunt.new(0, target: "cup"), [track("cup", age: 10, score: 0.4)], 100)
    assert hunt.phase == :hunting
  end

  test "other objects don't help" do
    hunt = Hunt.update(Hunt.new(0, target: "cup"), [track("bowl", age: 10)], 100)
    assert %{phase: :hunting, lock: +0.0} = hunt
  end

  test "after celebrating, a new target that wasn't just used" do
    hunt = Hunt.new(0, target: "cup") |> Hunt.update([track("cup", age: 4)], 100)

    still_celebrating = Hunt.update(hunt, [], 1_000)
    assert still_celebrating.phase == :found

    next = Hunt.update(hunt, [], 3_000)
    assert next.phase == :hunting
    assert next.target.class != "cup"
    assert next.target_started_at == 3_000
  end

  test "skipping moves on without points" do
    hunt = Hunt.skip(Hunt.new(0, target: "cup"), 500)
    assert %{score: 0, skipped: 1, phase: :hunting} = hunt
    assert hunt.target.class != "cup"
  end
end
