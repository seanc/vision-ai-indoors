defmodule IndoorsExperiments.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IndoorsExperimentsWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:indoors_experiments, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: IndoorsExperiments.PubSub},
      # Loads the YOLO model once and runs it for every camera session.
      IndoorsExperiments.Vision.Detector,
      # Start to serve requests, typically the last entry
      IndoorsExperimentsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: IndoorsExperiments.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    IndoorsExperimentsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
