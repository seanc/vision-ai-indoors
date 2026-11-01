defmodule IndoorsExperiments.Vision.YoloDecoder do
  @moduledoc """
  Turns YOLO's raw output tensor into a short list of detections.

  ## What the model gives us

  One tensor named `"output0"` with shape `{1, 84, 8400}`. Read it as a
  table with 8,400 columns, where each column is one *candidate* box the
  model considered, and 84 rows describing it:

      row 0..3    the box: center x, center y, width, height (in 640x640 pixels)
      row 4..83   a score from 0.0 to 1.0 for each of the 80 COCO classes

  Almost all 8,400 candidates are junk. Decoding is three filters:

    1. **Best class.** For each candidate keep only its highest class score.
    2. **Confidence threshold.** Drop candidates whose best score is low.
    3. **Non-maximum suppression (NMS).** The model usually proposes several
       nearly identical boxes around the same object. Keep the most confident
       one and drop any others that overlap it heavily.

  Finally, boxes are converted from 640x640 letterboxed pixels back into the
  original frame's pixels by undoing the letterbox (see `Preprocess`).
  """

  alias IndoorsExperiments.Vision.{Box, CocoClasses}

  # Candidates scoring below this are ignored.
  @min_score 0.35

  # Two boxes of the same class that overlap more than this are treated as duplicates.
  @nms_iou 0.45

  @doc """
  Returns a list of `%{class: "person", score: 0.91, box: %{x1, y1, x2, y2}}`,
  most confident first.
  """
  def decode(output, letterbox, frame) do
    output
    |> candidates()
    |> Enum.filter(fn candidate -> candidate.score >= @min_score end)
    |> non_max_suppression()
    |> Enum.map(fn det -> %{det | box: undo_letterbox(det.box, letterbox, frame)} end)
  end

  # Step 1: for every one of the 8400 columns, which class scored best and how well?
  #
  # We hand the table to OpenCV for this because it is ~700,000 numbers and
  # OpenCV can scan them in a few milliseconds. `reduce` with REDUCE_MAX
  # collapses each column to its largest value; `reduceArgMax` gives the row
  # number of that value instead, i.e. the class index.
  defp candidates(output) do
    table =
      output
      |> Nx.backend_transfer(Nx.BinaryBackend)
      |> Nx.reshape({84, 8400})

    class_scores = table |> Evision.Mat.from_nx_2d() |> Evision.Mat.roi({0, 4, 8400, 80})

    best_scores =
      class_scores
      |> Evision.reduce(0, Evision.Constant.cv_REDUCE_MAX())
      |> mat_to_list()

    best_classes =
      class_scores
      |> Evision.reduceArgMax(0)
      |> mat_to_list()

    # Rows 0..3 as four plain lists of 8400 numbers each.
    [center_xs, center_ys, widths, heights] =
      table
      |> Nx.slice([0, 0], [4, 8400])
      |> Nx.to_list()

    [center_xs, center_ys, widths, heights, best_scores, best_classes]
    |> Enum.zip_with(fn [cx, cy, w, h, score, class_index] ->
      %{
        class: CocoClasses.name(class_index),
        score: score,
        box: %{x1: cx - w / 2, y1: cy - h / 2, x2: cx + w / 2, y2: cy + h / 2}
      }
    end)
  end

  defp mat_to_list(mat), do: mat |> Evision.Mat.to_nx(Nx.BinaryBackend) |> Nx.to_flat_list()

  # Step 3: walk the candidates from most to least confident. Keep a candidate
  # unless we've already kept a box of the same class that overlaps it a lot.
  defp non_max_suppression(candidates) do
    candidates
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.reduce([], fn candidate, kept ->
      duplicate? =
        Enum.any?(kept, fn k ->
          k.class == candidate.class and Box.iou(k.box, candidate.box) > @nms_iou
        end)

      if duplicate?, do: kept, else: [candidate | kept]
    end)
    |> Enum.reverse()
  end

  # Remove the grey padding, then scale back up. Clamp to the frame edges.
  defp undo_letterbox(box, letterbox, frame) do
    to_frame_x = fn x -> clamp((x - letterbox.pad_left) / letterbox.scale, frame.width) end
    to_frame_y = fn y -> clamp((y - letterbox.pad_top) / letterbox.scale, frame.height) end

    %{
      x1: to_frame_x.(box.x1),
      y1: to_frame_y.(box.y1),
      x2: to_frame_x.(box.x2),
      y2: to_frame_y.(box.y2)
    }
  end

  defp clamp(value, limit), do: value |> max(0.0) |> min(limit * 1.0)
end
