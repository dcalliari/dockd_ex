defmodule Dockd.IGDBSyncTest do
  use Dockd.DataCase, async: false
  alias Dockd.{Catalog, IGDB, Repo}
  alias Dockd.Catalog.Game

  setup do
    Application.put_env(:dockd, :igdb,
      client_id: "test-id",
      client_secret: "test-secret",
      req_options: [plug: {Req.Test, "igdb-sync"}]
    )

    IGDB.clear_cache()
    on_exit(fn -> Application.put_env(:dockd, :igdb, []) end)
    :ok
  end

  test "maps metadata and platform dates, without changing availability" do
    external = game_response()
    stub_igdb(external)

    {:ok, game} =
      Catalog.create_game(%{title: "Local", availability: :nintendo_exclusive, igdb_id: 42})

    {:ok, _} = Catalog.sync_igdb()
    game = Repo.preload(Repo.get!(Game, game.id), :releases)
    assert game.cover_url =~ "cover-id"
    assert game.developer == "Dev"
    assert game.publisher == "Pub"
    assert game.availability == :nintendo_exclusive

    assert Enum.map(game.releases, &{&1.platform, &1.release_date}) == [
             {:switch, ~D[2024-01-01]},
             {:switch_2, ~D[2025-01-01]}
           ]

    assert Enum.all?(game.releases, & &1.digital_available)
  end

  test "sync is idempotent and does not duplicate releases" do
    stub_igdb(game_response())

    {:ok, game} =
      Catalog.create_game(%{title: "Local", availability: :multiplatform, igdb_id: 42})

    assert {:ok, _} = Catalog.sync_igdb()
    first = Repo.preload(Repo.get!(Game, game.id), :releases)
    assert {:ok, _} = Catalog.sync_igdb()
    second = Repo.preload(Repo.get!(Game, game.id), :releases)
    assert length(second.releases) == 2
    assert Enum.map(first.releases, & &1.id) == Enum.map(second.releases, & &1.id)
    assert Enum.map(first.releases, & &1.updated_at) == Enum.map(second.releases, & &1.updated_at)
  end

  test "stores the preferred regional date with its precision" do
    external = %{
      "id" => 42,
      "name" => "Local",
      "platforms" => [%{"id" => 130}, %{"id" => 508}],
      "release_dates" => [
        %{"platform" => 130, "region" => 1, "category" => 0, "date" => 1_704_067_200},
        %{"platform" => 130, "region" => 10, "category" => 0, "date" => 1_672_531_200},
        %{"platform" => 130, "region" => 8, "category" => 1, "date" => 1_735_689_600},
        %{"platform" => 508, "region" => 8, "category" => 7, "date" => 1_830_297_600}
      ]
    }

    stub_igdb(external)

    {:ok, game} =
      Catalog.create_game(%{title: "Local", availability: :multiplatform, igdb_id: 42})

    assert {:ok, _} = Catalog.sync_igdb()
    releases = Catalog.list_releases(game.id)
    switch = Enum.find(releases, &(&1.platform == :switch))
    switch_2 = Enum.find(releases, &(&1.platform == :switch_2))

    assert switch.release_date == ~D[2025-01-01]
    assert switch.release_date_precision == :month
    assert switch.digital_available
    assert switch_2.release_date == nil
    assert switch_2.release_date_precision == :tbd
    assert switch_2.digital_available
  end

  test "suggests Nintendo exclusivity for both Nintendo platforms only" do
    assert Catalog.suggested_availability(%{"platforms" => [%{"id" => 130}, %{"id" => 508}]}) ==
             :nintendo_exclusive

    assert Catalog.suggested_availability(%{
             "platforms" => [%{"id" => 130}, %{"id" => 508}, %{"id" => 6}]
           }) ==
             :multiplatform
  end

  test "a non Switch search result is never auto matched" do
    Req.Test.stub("igdb-sync", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          Req.Test.json(conn, [%{"id" => 7, "name" => "Local", "platforms" => [%{"id" => 6}]}])
      end
    end)

    {:ok, game} = Catalog.create_game(%{title: "Local", availability: :multiplatform})
    result = Catalog.match_igdb(dry_run: false)
    assert result.not_found != []
    assert Repo.get!(Game, game.id).igdb_id == nil
  end

  defp stub_igdb(game) do
    Req.Test.stub("igdb-sync", fn conn ->
      case conn.request_path do
        "/oauth2/token" -> Req.Test.json(conn, %{access_token: "token", expires_in: 3600})
        "/v4/games" -> Req.Test.json(conn, [game])
      end
    end)
  end

  defp game_response do
    %{
      "id" => 42,
      "name" => "Local",
      "cover" => %{"image_id" => "cover-id"},
      "involved_companies" => [
        %{"developer" => true, "publisher" => false, "company" => %{"name" => "Dev"}},
        %{"developer" => false, "publisher" => true, "company" => %{"name" => "Pub"}}
      ],
      "platforms" => [%{"id" => 130}, %{"id" => 508}],
      "release_dates" => [
        %{"platform" => 130, "date" => 1_704_067_200},
        %{"platform" => 508, "date" => 1_735_689_600}
      ]
    }
  end
end
