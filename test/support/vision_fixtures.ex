defmodule IndoorsExperiments.VisionFixtures do
  @moduledoc """
  Test images, and a fake "someone walks towards the camera" clip made by
  zooming further and further into a still photo.
  """

  @fixtures Path.expand("../fixtures", __DIR__)

  def jpeg(name), do: File.read!(Path.join(@fixtures, name))

  @doc """
  `count` JPEG frames that zoom into zidane.jpg, towards the man on the
  right. To the pipeline, he looks like he's getting closer and closer.
  """
  def approaching_frames(count, max_zoom \\ 1.8) do
    image = Evision.imdecode(jpeg("zidane.jpg"), Evision.Constant.cv_IMREAD_COLOR())
    {height, width, _} = image.shape

    # Zoom around a point at the bottom of the frame under the man on the right,
    # so he stays in the same place on screen while he grows.
    {anchor_x, anchor_y} = {0.74 * width, height}

    for step <- 0..(count - 1) do
      zoom = 1 + (max_zoom - 1) * step / (count - 1)
      crop_w = round(width / zoom)
      crop_h = round(height / zoom)
      crop_x = round(anchor_x * (1 - 1 / zoom))
      crop_y = round(anchor_y * (1 - 1 / zoom))

      image
      |> Evision.Mat.roi({crop_x, crop_y, crop_w, crop_h})
      |> Evision.resize({width, height})
      |> then(&Evision.imencode(".jpg", &1))
    end
  end
end
