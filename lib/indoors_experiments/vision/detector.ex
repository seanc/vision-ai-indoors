defmodule IndoorsExperiments.Vision.Detector do
  @moduledoc """
  Stage 2 of the pipeline: **perception**. JPEG in, list of objects out.

      JPEG --Preprocess--> {1,3,640,640} tensor --Ortex/YOLO--> {1,84,8400} --YoloDecoder--> detections

  The ONNX model is loaded once, when the app starts, and kept in
  `:persistent_term` (a global store built into the BEAM for things that
  are read constantly and almost never change). `detect/1` runs in the
  caller's process, so two browser tabs don't queue behind each other.

  This module is still a GenServer, but only so the app's supervisor has
  something to start: it loads the model, runs one throwaway "warm-up"
  frame (the very first call into OpenCV and ONNX Runtime is slow), and
  then just sits there.

  If the model file is missing the app still starts, and `detect/1` returns
  `{:error, :no_model}`. The streaming page keeps working (it just shows no
  boxes), which is handy for testing the camera/latency side on its own.
  """

  use GenServer
  require Logger

  alias IndoorsExperiments.Vision.{Preprocess, YoloDecoder}

  @model_key {__MODULE__, :model}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Runs the detector on one JPEG.

  Returns `{:ok, %{detections: [...], frame: %{width, height}, timings: %{...}}}`.
  Timings are in milliseconds so the page can show where the time goes.
  """
  def detect(jpeg) do
    case :persistent_term.get(@model_key, nil) do
      nil -> {:error, :no_model}
      model -> run(model, jpeg)
    end
  end

  @doc "Is a model loaded?"
  def ready?, do: :persistent_term.get(@model_key, nil) != nil

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :model_path, default_model_path())

    if File.exists?(path) do
      Logger.info("Loading YOLO model from #{path}")
      :persistent_term.put(@model_key, Ortex.load(path))
      {:ok, %{}, {:continue, :warm_up}}
    else
      Logger.warning("No model at #{path}. Run scripts/export_yolo.sh to create one.")
      {:ok, %{}}
    end
  end

  @impl true
  def handle_continue(:warm_up, state) do
    # A plain grey 640x480 picture. `from_nx_2d` reads {height, width, 3} as a
    # 2D image with 3 colour channels.
    grey = Nx.broadcast(Nx.tensor(114, type: :u8), {480, 640, 3})
    blank = Evision.imencode(".jpg", Evision.Mat.from_nx_2d(grey))
    {ms, _result} = :timer.tc(fn -> detect(blank) end, :millisecond)
    Logger.info("YOLO warm-up took #{ms} ms")
    {:noreply, state}
  end

  defp run(model, jpeg) do
    {prepare_ms, prepared} = timed(fn -> Preprocess.prepare(jpeg) end)

    case prepared do
      {:ok, %{input: input, letterbox: letterbox, frame: frame}} ->
        {model_ms, {output}} = timed(fn -> Ortex.run(model, input) end)
        {decode_ms, detections} = timed(fn -> YoloDecoder.decode(output, letterbox, frame) end)

        {:ok,
         %{
           detections: detections,
           frame: frame,
           timings: %{preprocess_ms: prepare_ms, model_ms: model_ms, decode_ms: decode_ms}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp timed(fun) do
    {microseconds, result} = :timer.tc(fun)
    {Float.round(microseconds / 1000, 1), result}
  end

  defp default_model_path do
    Application.app_dir(:indoors_experiments, "priv/models/yolo11n.onnx")
  end
end
