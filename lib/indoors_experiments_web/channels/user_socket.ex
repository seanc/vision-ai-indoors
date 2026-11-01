defmodule IndoorsExperimentsWeb.UserSocket do
  @moduledoc """
  The WebSocket the camera page connects to (`/socket`).
  Each browser tab opens one socket and joins one `vision:*` channel on it.
  """

  use Phoenix.Socket

  channel "vision:*", IndoorsExperimentsWeb.VisionChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
