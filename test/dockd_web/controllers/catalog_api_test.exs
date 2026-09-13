defmodule DockdWeb.CatalogApiTest do
  use DockdWeb.ConnCase, async: true
  alias Dockd.Catalog

  test "game routes return the catalog contract", %{conn: conn} do
    params = %{
      game: %{title: "Splatoon", availability: "multiplatform", other_platforms: ["Wii U"]}
    }

    conn = post(conn, ~p"/api/v1/games", params)

    assert %{"data" => %{"id" => id, "slug" => "splatoon", "releases" => []}} =
             json_response(conn, 201)

    assert %{"data" => %{"id" => ^id}} =
             put(conn, ~p"/api/v1/games/#{id}", %{
               game: %{title: "Splatoon 3", availability: "multiplatform"}
             })
             |> json_response(200)

    assert %{"data" => %{"id" => ^id}} = get(conn, ~p"/api/v1/games/#{id}") |> json_response(200)

    assert %{"data" => [%{"id" => ^id}]} =
             get(build_conn(), ~p"/api/v1/games") |> json_response(200)

    assert %{"error" => %{"type" => "validation"}} =
             post(build_conn(), ~p"/api/v1/games", %{game: %{availability: "multiplatform"}})
             |> json_response(422)
  end

  test "nested release routes return contract and validation errors", %{conn: conn} do
    {:ok, game} = Catalog.create_game(%{title: "Metroid", availability: :nintendo_exclusive})
    conn = post(conn, ~p"/api/v1/games/#{game.id}/releases", %{release: %{platform: "switch"}})

    assert %{"data" => %{"id" => release_id, "game_id" => _, "platform" => "switch"}} =
             json_response(conn, 201)

    assert %{"data" => %{"id" => ^release_id, "edition" => "Deluxe"}} =
             put(conn, ~p"/api/v1/games/#{game.id}/releases/#{release_id}", %{
               release: %{platform: "switch", edition: "Deluxe"}
             })
             |> json_response(200)

    assert %{"data" => [%{"platform" => "switch"}]} =
             get(build_conn(), ~p"/api/v1/games/#{game.id}/releases") |> json_response(200)

    assert %{"error" => %{"type" => "validation"}} =
             post(build_conn(), ~p"/api/v1/games/#{game.id}/releases", %{release: %{}})
             |> json_response(422)
  end
end
