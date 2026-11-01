defmodule IndoorsExperimentsWeb.PageController do
  use IndoorsExperimentsWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Camera")
  end
end
