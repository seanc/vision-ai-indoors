defmodule IndoorsExperimentsWeb.ChannelCase do
  @moduledoc """
  Test case for channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import IndoorsExperimentsWeb.ChannelCase

      @endpoint IndoorsExperimentsWeb.Endpoint
    end
  end
end
