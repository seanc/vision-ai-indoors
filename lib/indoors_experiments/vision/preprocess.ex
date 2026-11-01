defmodule IndoorsExperiments.Vision.Preprocess do
  @moduledoc """
  Turns a JPEG from the browser into the exact tensor YOLO expects.

  The model was exported with a fixed input: `"images"`, shape `{1, 3, 640, 640}`,
  float32, RGB, values from 0.0 to 1.0. A webcam frame is none of those things:

      what we get from Evision          what the model wants
      ------------------------          --------------------
      any size, e.g. 1280x720     -->   exactly 640x640
      BGR colour order            -->   RGB
      {height, width, channel}    -->   {batch, channel, height, width}
      bytes 0..255                -->   floats 0.0..1.0

  **Letterboxing** is the resize step. We shrink the frame until it fits in
  640x640 without stretching it, then fill the leftover strip with grey.
  We remember the scale and padding so the detector can convert boxes back
  into the original frame's pixels afterwards.
  """

  @model_size 640

  # Ultralytics pads with this grey, so we do too.
  @pad_colour {114, 114, 114}

  @doc """
  Returns `{:ok, %{input: tensor, letterbox: info, frame: %{width: w, height: h}}}`.
  """
  def prepare(jpeg) when is_binary(jpeg) do
    case Evision.imdecode(jpeg, Evision.Constant.cv_IMREAD_COLOR()) do
      %Evision.Mat{} = image ->
        {height, width, _channels} = image.shape
        {letterboxed, letterbox} = letterbox(image, width, height)

        {:ok,
         %{
           input: to_model_input(letterboxed),
           letterbox: letterbox,
           frame: %{width: width, height: height}
         }}

      _not_an_image ->
        {:error, :bad_jpeg}
    end
  end

  def model_size, do: @model_size

  # Scale to fit inside 640x640, then pad the rest. E.g. 1280x720 becomes
  # 640x360 and gets 140px of grey above and below.
  defp letterbox(image, width, height) do
    scale = min(@model_size / width, @model_size / height)
    new_width = round(width * scale)
    new_height = round(height * scale)

    pad_x = @model_size - new_width
    pad_y = @model_size - new_height
    pad_left = div(pad_x, 2)
    pad_top = div(pad_y, 2)

    letterboxed =
      image
      |> Evision.resize({new_width, new_height})
      |> Evision.copyMakeBorder(
        pad_top,
        pad_y - pad_top,
        pad_left,
        pad_x - pad_left,
        Evision.Constant.cv_BORDER_CONSTANT(),
        value: @pad_colour
      )

    {letterboxed, %{scale: scale, pad_left: pad_left, pad_top: pad_top}}
  end

  # `blobFromImage` is OpenCV's "get this image ready for a neural network"
  # function. With these options it does three of the steps in the table above
  # in one fast native call:
  #
  #   * scalefactor: 1/255  ->  0..255 bytes become 0.0..1.0 floats
  #   * swapRB: true        ->  BGR becomes RGB
  #   * (always)            ->  {H, W, C} becomes {1, C, H, W}
  #
  # The same thing in Nx would be:
  #
  #     image |> Evision.cvtColor(BGR2RGB) |> Evision.Mat.to_nx()
  #     |> Nx.divide(255) |> Nx.transpose(axes: [2, 0, 1]) |> Nx.new_axis(0)
  #
  # which reads nicely, but takes ~700ms per frame on Nx's pure-Elixir backend
  # versus ~3ms here.
  defp to_model_input(letterboxed) do
    letterboxed
    |> Evision.DNN.blobFromImage(scalefactor: 1 / 255, swapRB: true)
    |> Evision.Mat.to_nx(Nx.BinaryBackend)
  end
end
