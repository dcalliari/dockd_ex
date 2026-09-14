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
        game: %{title: "Splatoon 3", availability: "multiplatform"}
      })
      |> json_response(200)

    assert_schema(updated, "GameResponse", DockdWeb.ApiSpec.spec())
    assert %{"data" => %{"id" => ^id}} = updated

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
end
