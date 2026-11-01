defmodule IndoorsExperimentsWeb.VisionChannel do
  @moduledoc """
  One camera session. Frames come in, overlay data goes back.

  Phoenix starts one channel process per browser tab that joins, and that
  process stays alive until the tab closes. That makes it exactly the
  "one process per phone session" the architecture calls for: the session's
  `Pipeline` (its tracks and decision history) lives in this process's
  assigns and is thrown away when the tab goes.

  ## Messages

  The browser pushes `"frame"` as a single binary message (the format is in
  `IndoorsExperimentsWeb.FrameMessage`). We reply to each push with that
  frame's results. The browser only sends the next frame after the reply
  arrives, so frames never pile up here if the server is slower than the camera.

  The browser can also push `"client_log"` (errors, camera details, status
  changes) so problems on a phone end up in the session's `Recorder` files
  instead of only in a console nobody is looking at.
  """

  # Frames arrive several times a second; logging every one would bury
  # everything else in the server log.
  use Phoenix.Channel, log_handle_in: false
  require Logger

  alias IndoorsExperiments.Vision.{Detector, Pipeline, Recorder, Zones}
  alias IndoorsExperimentsWeb.FrameMessage

  @impl true
  def join("vision:" <> session_id, params, socket) do
    lane = Zones.lane_outline()

    recorder =
      Recorder.start(%{experiment: "hallway", session_id: session_id, client: params}, lane)

    socket =
      socket
      |> assign(:pipeline, Pipeline.new())
      |> assign(:recorder, recorder)

    {:ok, %{lane: lane, model_ready: Detector.ready?(), recording: recorder != nil}, socket}
  end

  @impl true
  def handle_in("frame", {:binary, message}, socket) do
    case FrameMessage.unpack(message) do
      {:ok, meta, jpeg} ->
        started = System.monotonic_time(:microsecond)
        {result, pipeline} = Pipeline.process(socket.assigns.pipeline, jpeg, meta)
        server_ms = (System.monotonic_time(:microsecond) - started) / 1000

        result = Map.merge(result, %{seq: meta["seq"], server_ms: Float.round(server_ms, 1)})
        recorder = Recorder.record_frame(socket.assigns.recorder, jpeg, meta, result)

        {:reply, {:ok, result}, assign(socket, pipeline: pipeline, recorder: recorder)}

      :error ->
        {:reply, {:error, %{reason: "malformed frame"}}, socket}
    end
  end

  def handle_in("client_log", event, socket) do
    Logger.info("[browser #{event["level"]}] #{event["message"]}")
    recorder = Recorder.record_event(socket.assigns.recorder, event)
    {:noreply, assign(socket, :recorder, recorder)}
  end
end
