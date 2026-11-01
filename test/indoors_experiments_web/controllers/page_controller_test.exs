defmodule IndoorsExperimentsWeb.PageControllerTest do
  use IndoorsExperimentsWeb.ConnCase

  test "GET / renders the camera page", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    for id <- ~w(vision-app video overlay start-camera decision track-list) do
      assert LazyHTML.query(html, "##{id}") |> Enum.count() == 1, "missing ##{id}"
    end
  end
end
