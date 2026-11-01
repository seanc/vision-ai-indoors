defmodule IndoorsExperimentsWeb.FrameMessage do
  @moduledoc """
  The binary format the browser uses to send a frame (see `sendFrame` in
  `assets/js/vision/connection.js`):

      <<header_size::32, header_json::binary-size(header_size), jpeg::binary>>

  The JPEG travels as raw bytes, so it isn't inflated by base64 (which would
  add a third to every frame). `header_json` holds the metadata: `seq`
  (frame counter), `t` (capture time in ms), `orientation` (or null) and
  `client` (the browser's timings for the previous frame).
  """

  @doc "Returns `{:ok, meta, jpeg}` or `:error`."
  def unpack(<<header_size::32, header::binary-size(header_size), jpeg::binary>>) do
    case Jason.decode(header) do
      {:ok, meta} -> {:ok, meta, jpeg}
      {:error, _} -> :error
    end
  end

  def unpack(_other), do: :error
end
