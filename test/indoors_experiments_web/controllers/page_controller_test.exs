defmodule IndoorsExperimentsWeb.PageControllerTest do
  use IndoorsExperimentsWeb.ConnCase

  @shared ~w(stage video overlay start-camera focus-enter focus-exit status)

  test "GET / renders the hallway page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    assert_ids(html, ~w(vision-app decision track-list hud-decision) ++ @shared)
  end

  test "GET /hunt renders the scavenger hunt", %{conn: conn} do
    html = conn |> get(~p"/hunt") |> html_response(200) |> LazyHTML.from_document()
    assert_ids(html, ~w(hunt-app hunt-target hunt-skip hunt-seeing hunt-celebrate) ++ @shared)
  end

  defp assert_ids(html, ids) do
    for id <- ids do
      assert LazyHTML.query(html, "##{id}") |> Enum.count() == 1, "missing ##{id}"
    end
  end
end
