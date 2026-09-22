defmodule DockdWeb.PlannerWalletLiveTest do
  use DockdWeb.ConnCase

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Accounts
  alias Dockd.Library

  test "the root is the list and exposes only the discovery flow", %{conn: conn} do
    game = game_fixture(%{title: "Root list game"})

    {:ok, _entry} =
      Library.create_entry(Accounts.default_owner(), %{game_id: game.id, purchase_intent: :want})

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#list")
    assert has_element?(view, "#list-game-#{game.id}")
    assert has_element?(view, "nav a", "Descobrir")
    refute has_element?(view, "nav a", "Carteira")
    refute has_element?(view, "nav a", "Planejador")
  end

  test "routes from later flows return not found", %{conn: conn} do
    assert response = get(conn, "/carteira")
    assert response.status == 404
  end
end
