defmodule Dockd.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        DockdWeb.Telemetry,
        Dockd.Repo,
        {DNSCluster, query: Application.get_env(:dockd, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Dockd.PubSub},
        # Start a worker by calling: Dockd.Worker.start_link(arg)
        # {Dockd.Worker, arg},
        # Start to serve requests, typically the last entry
        DockdWeb.Endpoint
      ] ++ if sync?(), do: [Dockd.IGDB.SyncScheduler], else: []

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dockd.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Where the machine stops when idle (Fly), a daily run inside it would die halfway;
  # there `CATALOG_SYNC_SCHEDULER=false` leaves the sync to `Dockd.Release.sync/0`.
  defp sync? do
    scheduled? = :dockd |> Application.get_env(:igdb, []) |> Keyword.get(:sync_scheduler, true)
    scheduled? and (Dockd.IGDB.configured?() or Dockd.Eshop.configured?())
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DockdWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
