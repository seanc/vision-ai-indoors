defmodule IndoorsExperimentsWeb.HuntChannel do
  @moduledoc """
  One scavenger-hunt session. Works exactly like `VisionChannel` (one
  process per browser tab, binary frames in, results out) but runs
  `HuntPipeline` instead of the hallway `Pipeline`.

  Messages from the browser:

    * `"frame"`: a binary frame (see `IndoorsExperimentsWeb.FrameMessage`)
    * `"skip"`: give up on the current target, `%{"t" => now_ms}`
    * `"client_log"`: errors and camera details, for the recording

  The game starts on the first frame rather than on join, so that all game
  times come from the browser's clock, like the frame timestamps do.
  """

  # Frames arrive several times a second; logging every one would bury
  # everything else in the server log.
  use Phoenix.Channel, log_handle_in: false
  require Logger

  alias IndoorsExperiments.Vision.{Detector, Hunt, HuntPipeline, Recorder}
  alias IndoorsExperimentsWeb.FrameMessage

  @impl true
  def join("hunt:" <> session_id, params, socket) do
    recorder = Recorder.start(%{experiment: "hunt", session_id: session_id, client: params}, nil)

    socket =
      socket
      |> assign(:pipeline, nil)
      |> assign(:recorder, recorder)
      # Debugging aid: /hunt?target=bus makes the first target a bus.
      |> assign(:first_target, params["target"])

    reply = %{targets: Hunt.targets(), model_ready: Detector.ready?(), recording: recorder != nil}
    {:ok, reply, socket}
  end

  @impl true
  def handle_in("frame", {:binary, message}, socket) do
    case FrameMessage.unpack(message) do
      {:ok, meta, jpeg} ->
        started = System.monotonic_time(:microsecond)

        pipeline =
          socket.assigns.pipeline ||
            HuntPipeline.new(meta["t"], target: socket.assigns.first_target)

        {result, pipeline} = HuntPipeline.process(pipeline, jpeg, meta)
        server_ms = (System.monotonic_time(:microsecond) - started) / 1000

        result = Map.merge(result, %{seq: meta["seq"], server_ms: Float.round(server_ms, 1)})
        recorder = Recorder.record_frame(socket.assigns.recorder, jpeg, meta, result)

        {:reply, {:ok, result}, assign(socket, pipeline: pipeline, recorder: recorder)}

      :error ->
        {:reply, {:error, %{reason: "malformed frame"}}, socket}
    end
  end

  def handle_in("skip", %{"t" => now}, %{assigns: %{pipeline: %HuntPipeline{}}} = socket) do
    pipeline = HuntPipeline.skip(socket.assigns.pipeline, now)

    recorder =
      Recorder.record_event(socket.assigns.recorder, %{"level" => "info", "message" => "skipped"})

    {:reply, {:ok, %{hunt: HuntPipeline.summary(pipeline, now)}},
     assign(socket, pipeline: pipeline, recorder: recorder)}
  end

  # Skip pressed before the first frame: nothing to skip yet.
  def handle_in("skip", _payload, socket),
    do: {:reply, {:error, %{reason: "not started"}}, socket}

  def handle_in("client_log", event, socket) do
    Logger.info("[browser #{event["level"]}] #{event["message"]}")
    recorder = Recorder.record_event(socket.assigns.recorder, event)
    {:noreply, assign(socket, :recorder, recorder)}
  end
end
