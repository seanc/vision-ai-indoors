defmodule IndoorsExperiments.Vision.Box do
  @moduledoc """
  Small helpers for bounding boxes.

  A box is a plain map of pixel coordinates in the ORIGINAL camera frame:

      %{x1: left, y1: top, x2: right, y2: bottom}

  (0, 0) is the top-left corner of the image, and y grows downwards.
  """

  def width(box), do: box.x2 - box.x1
  def height(box), do: box.y2 - box.y1
  def area(box), do: width(box) * height(box)

  @doc """
  One number for "how big is this box".

  It's the square root of the area, so it grows at the same rate as the
  width and height do. A box that doubles in width and height has a
  size that doubles too (its area would quadruple).
  """
  def size(box), do: :math.sqrt(area(box))

  def center(box), do: %{x: (box.x1 + box.x2) / 2, y: (box.y1 + box.y2) / 2}

  @doc """
  The middle of the box's bottom edge: roughly where an object touches the floor.
  This is the point we use to decide which zone an object is standing in.
  """
  def bottom_center(box), do: %{x: (box.x1 + box.x2) / 2, y: box.y2}

  @doc """
  Intersection over Union: how much two boxes overlap, from 0.0 to 1.0.

    * 0.0 means they don't touch at all
    * 1.0 means they are exactly the same box

  It's the area they share divided by the area they cover together.
  """
  def iou(a, b) do
    # The overlapping rectangle (if any) is bounded by the inner-most edges.
    overlap_w = min(a.x2, b.x2) - max(a.x1, b.x1)
    overlap_h = min(a.y2, b.y2) - max(a.y1, b.y1)

    if overlap_w <= 0 or overlap_h <= 0 do
      0.0
    else
      shared = overlap_w * overlap_h
      combined = area(a) + area(b) - shared
      shared / combined
    end
  end
end
