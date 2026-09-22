defmodule Dockd.IGDBRequirementsTest do
  use Dockd.DataCase, async: false
  import OpenApiSpex.TestAssertions
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  alias Dockd.{Activity, Catalog, IGDB, Library, Purchasing, Repo, Wallet}
  alias Dockd.Catalog.Game
  alias DockdWeb.ApiSpec
  @endpoint DockdWeb.Endpoint

  setup do
    Application.put_env(:dockd, :igdb,
      client_id: "test-id",
      client_secret: "test-secret",
      req_options: [plug: {Req.Test, "igdb-requirements"}]
    )

    IGDB.clear_cache()
    on_exit(fn -> Application.put_env(:dockd, :igdb, []) end)
    :ok
  end

  test "refreshes expired tokens and retries throttled and server failures" do
    counter = start_supervised!({Agent, fn -> %{tokens: 0, games: 0} end})

    Req.Test.stub("igdb-requirements", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Agent.update(counter, &Map.update!(&1, :tokens, fn value -> value + 1 end))
          Req.Test.json(conn, %{access_token: "token", expires_in: 0})

        "/v4/games" ->
          attempt =
            Agent.get_and_update(counter, fn state ->
              {state.games, %{state | games: state.games + 1}}
            end)

          case attempt do
            0 -> Plug.Conn.resp(conn, 429, "slow down")
            1 -> Plug.Conn.resp(conn, 503, "unavailable")
            _ -> Req.Test.json(conn, [])
          end
      end
    end)

    assert {:ok, _} = IGDB.search("first")
    assert {:ok, _} = IGDB.search("second")
    assert Agent.get(counter, & &1.tokens) == 2
    assert Agent.get(counter, & &1.games) == 4
  end

  test "isolates one failed game from the rest of a sync" do
    Req.Test.stub("igdb-requirements", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          if String.contains?(conn.adapter |> elem(1) |> Map.get(:raw_body), "where id = (1)"),
            do: Plug.Conn.resp(conn, 500, "broken"),
            else: Req.Test.json(conn, [game_response(2, "Good")])
      end
    end)

    {:ok, failed} =
      Catalog.create_game(%{title: "Failed", availability: :multiplatform, igdb_id: 1})

    {:ok, good} = Catalog.create_game(%{title: "Good", availability: :multiplatform, igdb_id: 2})

    assert {:ok, %{synced: 1, results: results}} = Catalog.sync_igdb()

    assert Enum.any?(results, fn
             {:error, {id, _}} -> id == failed.id
             _ -> false
           end)

    assert Repo.get!(Game, good.id).cover_url =~ "cover-2"
  end

  test "classifies switch candidates, rejects non Switch candidates and honors dry run" do
    Req.Test.stub("igdb-requirements", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          body = conn.adapter |> elem(1) |> Map.get(:raw_body)

          response =
            cond do
              String.contains?(body, "Ambiguous") ->
                [candidate(10, "Ambiguous", 130), candidate(11, "Ambiguous", 508)]

              String.contains?(body, "No Switch") ->
                [candidate(12, "No Switch", 6), candidate(13, "No Switch", 7)]

              true ->
                [candidate(14, "Clean", 130)]
            end

          Req.Test.json(conn, response)
      end
    end)

    {:ok, ambiguous} = Catalog.create_game(%{title: "Ambiguous", availability: :multiplatform})
    {:ok, absent} = Catalog.create_game(%{title: "No Switch", availability: :multiplatform})
    {:ok, clean} = Catalog.create_game(%{title: "Clean", availability: :multiplatform})

    result = Catalog.match_igdb(dry_run: true)
    assert length(result.ambiguous) == 1
    assert length(result.not_found) == 1
    assert length(result.matched) == 1
    assert Repo.get!(Game, ambiguous.id).igdb_id == nil
    assert Repo.get!(Game, absent.id).igdb_id == nil
    assert Repo.get!(Game, clean.id).igdb_id == nil

    result = Catalog.match_igdb()
    assert hd(result.matched).candidate["id"] == 14
    assert Repo.get!(Game, clean.id).igdb_id == 14
  end

  test "matches normalized exact names and rejects misleading unique results" do
    Req.Test.stub("igdb-requirements", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          body = conn.adapter |> elem(1) |> Map.get(:raw_body)

          response =
            cond do
              String.contains?(body, "Donkey Kong Bananza") ->
                [candidate(10, "Donkey Kong: Bananza", 130)]

              String.contains?(body, "Hollow Knight") ->
                [
                  candidate(11, "Different Name", 130)
                  |> Map.put("alternative_names", [%{"name" => "Hollow Knight"}]),
                  candidate(12, "Hollow Knight", 130)
                ]

              String.contains?(body, "Out of Words") ->
                [candidate(13, "Words in Word", 130)]

              String.contains?(body, "Pokemon Epee") ->
                [candidate(14, "Pokémon Épée", 130)]

              true ->
                []
            end

          Req.Test.json(conn, response)
      end
    end)

    {:ok, exact} =
      Catalog.create_game(%{title: "Donkey Kong Bananza", availability: :multiplatform})

    {:ok, ambiguous} =
      Catalog.create_game(%{title: "Hollow Knight", availability: :multiplatform})

    {:ok, wrong} = Catalog.create_game(%{title: "Out of Words", availability: :multiplatform})

    {:ok, normalized} =
      Catalog.create_game(%{title: "Pokemon Epee", availability: :multiplatform})

    result = Catalog.match_igdb()

    assert Enum.any?(result.matched, &(&1.title == exact.title and &1.candidate["id"] == 10))
    assert Enum.any?(result.matched, &(&1.title == normalized.title and &1.candidate["id"] == 14))
    assert Enum.any?(result.ambiguous, &(&1.title == ambiguous.title))
    assert Enum.any?(result.not_found, &(&1.title == wrong.title))
    assert Repo.get!(Game, wrong.id).igdb_id == nil
  end

  test "scheduler runs matching before the initial synchronization" do
    Req.Test.stub("igdb-requirements", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          body = conn.adapter |> elem(1) |> Map.get(:raw_body)

          if String.contains?(body, "where id") do
            Req.Test.json(conn, [game_response(88, "Scheduled")])
          else
            Req.Test.json(conn, [candidate(88, "Scheduled", 130)])
          end
      end
    end)

    Application.put_env(:dockd, :igdb,
      client_id: "test-id",
      client_secret: "test-secret",
      sync_initial_delay: 60_000,
      sync_interval: 60_000,
      req_options: [plug: {Req.Test, "igdb-requirements"}]
    )

    {:ok, game} = Catalog.create_game(%{title: "Scheduled", availability: :multiplatform})
    scheduler = start_supervised!(Dockd.IGDB.SyncScheduler)
    send(scheduler, :initial_sync)
    _ = :sys.get_state(scheduler)

    assert Repo.get!(Game, game.id).igdb_id == 88
    assert [%{digital_available: true}] = Catalog.list_releases(game.id)
  end

  test "sync and import leave personal records and events untouched" do
    Req.Test.stub("igdb-requirements", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          body = conn.adapter |> elem(1) |> Map.get(:raw_body)
          imported? = String.contains?(body, "where id = (43)")
          title = if imported?, do: "Imported", else: "Synced"
          id = if imported?, do: 43, else: 42
          Req.Test.json(conn, [game_response(id, title)])
      end
    end)

    {:ok, game} =
      Catalog.create_game(%{title: "Synced", availability: :multiplatform, igdb_id: 42})

    before = table_counts()
    assert {:ok, _} = Catalog.sync_igdb()
    assert {:created, _} = import_game()
    assert table_counts() == before
    assert Repo.get!(Game, game.id).availability == :multiplatform
  end

  test "IGDB routes validate success responses and document not configured errors" do
    Req.Test.stub("igdb-requirements", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          body = conn.adapter |> elem(1) |> Map.get(:raw_body)
          title = if String.contains?(body, "where id"), do: "Synced", else: "Imported"
          Req.Test.json(conn, [game_response(99, title)])
      end
    end)

    conn = build_conn() |> put_req_header("content-type", "application/json")

    assert_schema(
      get(conn, "/api/v1/igdb/search?q=Imported") |> json_response(200),
      "IGDBSearchResponse",
      ApiSpec.spec()
    )

    assert_schema(
      post(build_conn(), "/api/v1/igdb/games/99/import", %{}) |> json_response(201),
      "GameResponse",
      ApiSpec.spec()
    )

    assert_schema(
      post(build_conn(), "/api/v1/igdb/sync", %{}) |> json_response(200),
      "IGDBSyncResponse",
      ApiSpec.spec()
    )

    assert_schema(
      post(build_conn(), "/api/v1/igdb/match", %{}) |> json_response(200),
      "IGDBMatchResponse",
      ApiSpec.spec()
    )

    Application.put_env(:dockd, :igdb, client_id: nil, client_secret: nil)

    assert json_response(get(build_conn(), "/api/v1/igdb/search?q=x"), 503)["error"]["type"] ==
             "not_configured"

    assert json_response(post(build_conn(), "/api/v1/igdb/games/100/import", %{}), 503)["error"][
             "type"
           ] == "not_configured"

    assert json_response(post(build_conn(), "/api/v1/igdb/sync", %{}), 503)["error"]["type"] ==
             "not_configured"

    assert json_response(post(build_conn(), "/api/v1/igdb/match", %{}), 503)["error"]["type"] ==
             "not_configured"
  end

  defp import_game do
    conn = build_conn() |> put_req_header("content-type", "application/json")
    {:created, post(conn, "/api/v1/igdb/games/43/import", %{}) |> json_response(201)}
  end

  defp table_counts do
    %{
      entries: Repo.aggregate(Library.Entry, :count),
      ownerships: Repo.aggregate(Library.Ownership, :count),
      purchases: Repo.aggregate(Purchasing.Purchase, :count),
      price_observations: Repo.aggregate(Purchasing.PriceObservation, :count),
      vetoes: Repo.aggregate(Library.ReleaseVeto, :count),
      store_balances: Repo.aggregate(Wallet.StoreBalance, :count),
      balance_reservations: Repo.aggregate(Wallet.BalanceReservation, :count),
      events: Repo.aggregate(Activity.Event, :count)
    }
  end

  defp candidate(id, name, platform),
    do: %{"id" => id, "name" => name, "platforms" => [%{"id" => platform}]}

  defp game_response(id, title),
    do: %{
      "id" => id,
      "name" => title,
      "cover" => %{"image_id" => "cover-#{id}"},
      "involved_companies" => [],
      "platforms" => [%{"id" => 130}],
      "release_dates" => []
    }
end
