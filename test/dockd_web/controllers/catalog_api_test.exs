defmodule DockdWeb.CatalogApiTest do
  use DockdWeb.ConnCase, async: true
  import OpenApiSpex.TestAssertions
  alias Dockd.Catalog

  test "game routes return the catalog contract", %{conn: conn} do
    params = %{
      game: %{title: "Splatoon", availability: "multiplatform", other_platforms: ["Wii U"]}
    }

    conn = put_req_header(conn, "content-type", "application/json")
    created = post(conn, ~p"/api/v1/games", params) |> json_response(201)
    assert_schema(created, "GameResponse", DockdWeb.ApiSpec.spec())
    assert %{"data" => %{"id" => id, "slug" => "splatoon", "releases" => []}} = created

    updated =
      put(conn, ~p"/api/v1/games/#{id}", %{
        game: %{title: "Splatoon 3", availability: "multiplatform", igdb_id: 27_239}
      })
      |> json_response(200)

    assert_schema(updated, "GameResponse", DockdWeb.ApiSpec.spec())
    assert %{"data" => %{"id" => ^id, "igdb_id" => 27_239}} = updated

    duplicate =
      post(conn, ~p"/api/v1/games", %{
        game: %{
          title: "Duplicate IGDB",
          availability: "multiplatform",
          igdb_id: 27_239
        }
      })
      |> json_response(422)

    assert_schema(duplicate, "ValidationError", DockdWeb.ApiSpec.spec())
    assert %{"error" => %{"details" => %{"igdb_id" => [_]}}} = duplicate

    shown = get(conn, ~p"/api/v1/games/#{id}") |> json_response(200)
    assert_schema(shown, "GameResponse", DockdWeb.ApiSpec.spec())
    listed = get(build_conn(), ~p"/api/v1/games") |> json_response(200)
    assert_schema(listed, "GameListResponse", DockdWeb.ApiSpec.spec())
    assert %{"data" => [%{"id" => ^id}]} = listed

    invalid =
      post(build_conn(), ~p"/api/v1/games", %{game: %{availability: "multiplatform"}})
      |> json_response(422)

    assert_schema(invalid, "ValidationError", DockdWeb.ApiSpec.spec())
    assert %{"error" => %{"type" => "validation"}} = invalid
  end

  test "nested release routes return contract and validation errors", %{conn: conn} do
    {:ok, game} = Catalog.create_game(%{title: "Metroid", availability: :nintendo_exclusive})
    conn = put_req_header(conn, "content-type", "application/json")

    created =
      post(conn, ~p"/api/v1/games/#{game.id}/releases", %{release: %{platform: "switch"}})
      |> json_response(201)

    assert_schema(created, "ReleaseResponse", DockdWeb.ApiSpec.spec())
    assert %{"data" => %{"id" => release_id, "game_id" => _, "platform" => "switch"}} = created

    updated =
      put(conn, ~p"/api/v1/games/#{game.id}/releases/#{release_id}", %{
        release: %{platform: "switch", edition: "Deluxe"}
      })
      |> json_response(200)

    assert_schema(updated, "ReleaseResponse", DockdWeb.ApiSpec.spec())
    assert %{"data" => %{"id" => ^release_id, "edition" => "Deluxe"}} = updated

    shown = get(conn, ~p"/api/v1/games/#{game.id}/releases/#{release_id}") |> json_response(200)
    assert shown["data"]["release_date_precision"] == "tbd"
    assert_schema(shown, "ReleaseResponse", DockdWeb.ApiSpec.spec())
    listed = get(build_conn(), ~p"/api/v1/games/#{game.id}/releases") |> json_response(200)
    assert_schema(listed, "ReleaseListResponse", DockdWeb.ApiSpec.spec())
    assert %{"data" => [%{"platform" => "switch"}]} = listed

    invalid =
      post(build_conn(), ~p"/api/v1/games/#{game.id}/releases", %{release: %{}})
      |> json_response(422)

    assert_schema(invalid, "ValidationError", DockdWeb.ApiSpec.spec())
    assert %{"error" => %{"type" => "validation"}} = invalid
  end

  test "generated OpenAPI schemas expose catalog fields", %{conn: conn} do
    spec = DockdWeb.ApiSpec.spec()
    game_attributes = spec.components.schemas["GameAttributes"]
    game = spec.components.schemas["Game"]
    release = spec.components.schemas["Release"]

    assert Map.has_key?(game_attributes.properties, :igdb_id)
    assert game_attributes.properties[:igdb_id].type == :integer
    assert game_attributes.properties[:igdb_id].nullable
    assert Map.has_key?(game_attributes.properties, :cover_url)
    refute Map.has_key?(game_attributes.properties, :synced_at)
    assert Map.has_key?(game.properties, :igdb_id)
    assert Map.has_key?(release.properties, :release_date_precision)

    response = get(conn, "/api/openapi") |> json_response(200)
    assert response["components"]["schemas"]["GameAttributes"]["properties"]["igdb_id"]
    assert response["components"]["schemas"]["Release"]["properties"]["release_date_precision"]
  end

  test "deletes an orphan release and protects releases with ownership", %{conn: conn} do
    {:ok, game} = Catalog.create_game(%{title: "Sports Resort", availability: :switch2_exclusive})
    {:ok, orphan} = Catalog.create_release(game.id, %{platform: :switch})
    conn = put_req_header(conn, "content-type", "application/json")

    assert conn
           |> delete(~p"/api/v1/games/#{game.id}/releases/#{orphan.id}")
           |> response(204) == ""

    {:ok, owned} = Catalog.create_release(game.id, %{platform: :switch_2})
    user = Dockd.Accounts.default_owner()

    assert {:ok, _ownership} =
             Dockd.Library.create_ownership(user, %{
               release_id: owned.id,
               ownership_type: :digital,
               acquired_at: DateTime.utc_now()
             })

    conflict =
      conn
      |> delete(~p"/api/v1/games/#{game.id}/releases/#{owned.id}")
      |> json_response(409)

    assert conflict["error"]["type"] == "conflict"
    assert "ownership" in conflict["error"]["blockers"]
  end

  test "returns not found for a release belonging to another game", %{conn: conn} do
    {:ok, game} = Catalog.create_game(%{title: "First game", availability: :nintendo_exclusive})

    {:ok, other_game} =
      Catalog.create_game(%{title: "Other game", availability: :nintendo_exclusive})

    {:ok, release} = Catalog.create_release(other_game.id, %{platform: :switch})

    assert_error_sent 404, fn ->
      delete(conn, ~p"/api/v1/games/#{game.id}/releases/#{release.id}")
    end
  end
end
