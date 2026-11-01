defmodule IndoorsExperimentsWeb.PageHTML do
  @moduledoc """
  The experiment pages. See the `page_html` directory for the templates.
  """
  use IndoorsExperimentsWeb, :html

  import IndoorsExperimentsWeb.CameraComponents

  embed_templates "page_html/*"
end
