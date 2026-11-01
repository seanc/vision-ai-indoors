defmodule IndoorsExperimentsWeb.UserSocket do
  @moduledoc """
  The WebSocket the camera page connects to (`/socket`).
  Each browser tab opens one socket and joins one channel on it:
  `vision:*` for the hallway page, `hunt:*` for the scavenger hunt.
  """

  use Phoenix.Socket

  channel "vision:*", IndoorsExperimentsWeb.VisionChannel
  channel "hunt:*", IndoorsExperimentsWeb.HuntChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
