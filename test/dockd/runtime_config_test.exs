defmodule Dockd.RuntimeConfigTest do
  use ExUnit.Case, async: false

  test "uses numeric defaults when runtime environment variables are empty" do
    variables = [
      {"PORT", ""},
      {"POOL_SIZE", ""},
      {"IGDB_SYNC_INITIAL_DELAY_MS", ""},
      {"IGDB_SYNC_INTERVAL_MS", ""}
    ]

    previous = Enum.map(variables, fn {name, _value} -> {name, System.get_env(name)} end)

    Enum.each(variables, fn {name, value} -> System.put_env(name, value) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    config = Config.Reader.read!("config/runtime.exs", env: :test)
    dockd_config = Keyword.fetch!(config, :dockd)
    endpoint_config = Keyword.fetch!(dockd_config, DockdWeb.Endpoint)
    igdb_config = Keyword.fetch!(dockd_config, :igdb)

    assert Keyword.fetch!(endpoint_config, :http) == [port: 4000]
    assert Keyword.fetch!(igdb_config, :sync_initial_delay) == 1_000
    assert Keyword.fetch!(igdb_config, :sync_interval) == 86_400_000
  end
end
