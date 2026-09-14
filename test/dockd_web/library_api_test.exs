defmodule DockdWeb.LibraryApiTest do
  use DockdWeb.ConnCase, async: false
  import Dockd.DomainFixtures
  import Phoenix.ConnTest
  alias Dockd.Accounts
  alias Dockd.Library

  setup %{conn: conn} do
    game = game_fixture(%{title: "Super Mario Bros. Wonder"})
    {:ok, conn: put_req_header(conn, "content-type", "application/json"), game: game}
  end

  test "entries CRUD", %{conn: conn, game: game} do
    attrs = %{entry: %{game_id: game.id, purchase_intent: "want", target_price_cents: 19_990}}
    response = conn |> post("/api/v1/entries", Jason.encode!(attrs)) |> json_response(201)
    entry_id = response["data"]["id"]
    assert response["data"]["game_id"] == game.id
    assert get(conn, "/api/v1/entries") |> json_response(200) |> get_in(["data"]) != []
    assert get(conn, "/api/v1/entries/#{entry_id}") |> json_response(200)

    assert conn
           |> put("/api/v1/entries/#{entry_id}", Jason.encode!(%{entry: %{backlog: "backlog"}}))
           |> json_response(200)

    assert delete(conn, "/api/v1/entries/#{entry_id}") |> response(204)
  end

  test "entries return validation errors", %{conn: conn} do
    assert %{"error" => %{"type" => "validation"}} =
             conn |> post("/api/v1/entries", Jason.encode!(%{entry: %{}})) |> json_response(422)
  end

  test "ownerships CRUD and validation", %{conn: conn, game: game} do
    release = release_fixture(game)

    attrs = %{
      ownership: %{
        release_id: release.id,
        ownership_type: "digital",
        acquired_at: DateTime.utc_now()
      }
    }

    response = conn |> post("/api/v1/ownerships", Jason.encode!(attrs)) |> json_response(201)
    ownership_id = response["data"]["id"]
    assert get(conn, "/api/v1/ownerships") |> json_response(200)
    assert get(conn, "/api/v1/ownerships/#{ownership_id}") |> json_response(200)

    assert conn
           |> put(
             "/api/v1/ownerships/#{ownership_id}",
             Jason.encode!(%{ownership: %{ownership_type: "borrowed"}})
           )
           |> json_response(200)

    assert delete(conn, "/api/v1/ownerships/#{ownership_id}") |> response(204)

    assert %{"error" => %{"type" => "validation"}} =
             conn
             |> post("/api/v1/ownerships", Jason.encode!(%{ownership: %{}}))
             |> json_response(422)

    assert Accounts.default_owner()
    assert Library.list_ownerships(Accounts.default_owner()) == []
  end
end
