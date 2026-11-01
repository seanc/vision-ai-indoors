defmodule IndoorsExperimentsWeb.PageController do
  use IndoorsExperimentsWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Hallway")
  end

  def hunt(conn, _params) do
    render(conn, :hunt, page_title: "Scavenger hunt")
  end
end
