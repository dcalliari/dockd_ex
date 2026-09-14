defmodule Dockd.IGDBTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.get_env(:dockd, :igdb)

    Application.put_env(:dockd, :igdb,
      client_id: "test-id",
      client_secret: "test-secret",
      req_options: [plug: {Req.Test, "igdb"}]
    )

    Dockd.IGDB.clear_cache()
    on_exit(fn -> Application.put_env(:dockd, :igdb, previous || []) end)
    :ok
  end

  test "caches an access token between requests" do
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub("igdb", fn conn ->
      Agent.update(counter, &(&1 + 1))

      case conn.request_path do
        "/oauth2/token" -> Req.Test.json(conn, %{access_token: "cached", expires_in: 3600})
        "/v4/games" -> Req.Test.json(conn, [])
      end
    end)

    assert {:ok, _} = Dockd.IGDB.search("one")
    assert {:ok, _} = Dockd.IGDB.search("two")
    assert Agent.get(counter, & &1) == 3
  end

  test "reports missing credentials without making requests" do
    Application.put_env(:dockd, :igdb, client_id: nil, client_secret: nil)
    refute Dockd.IGDB.configured?()
    assert {:error, :not_configured} = Dockd.Catalog.sync_igdb()
  end
end
