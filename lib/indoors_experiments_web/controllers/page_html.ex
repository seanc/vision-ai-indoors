defmodule IndoorsExperimentsWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use IndoorsExperimentsWeb, :html

  embed_templates "page_html/*"

  attr :id, :string, required: true
  attr :label, :string, required: true

  @doc "One number in the latency panel. The JS fills in the value by id."
  def stat(assigns) do
    ~H"""
    <div>
      <dd id={@id} class="font-mono text-base font-semibold text-slate-100 tabular-nums">–</dd>
      <dt class="text-[11px] text-slate-500">{@label}</dt>
    </div>
    """
  end

  @doc "Segments of the latency bar, in the order a frame goes through them."
  def latency_segments do
    [
      {"capture", "bg-sky-400"},
      {"network", "bg-slate-400"},
      {"preprocess", "bg-violet-400"},
      {"model", "bg-emerald-400"},
      {"decode", "bg-amber-400"},
      {"track", "bg-rose-400"}
    ]
  end
end
