defmodule DockdWeb.CatalogLibraryTest do
  use DockdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures
  alias Dockd.Accounts
  alias Dockd.Library

  test "filters catalog discovery by title", %{conn: conn} do
    game_fixture(%{title: "Unique discovery title"})
    game_fixture(%{title: "Another title"})

    {:ok, view, _html} = live(conn, "/catalogo")
    assert has_element?(view, "#catalog-search-form")

    view
    |> form("#catalog-search-form", catalog: %{search: "Unique discovery"})
    |> render_change()

    assert has_element?(view, "#games-list article h2", "Unique discovery title")
    refute has_element?(view, "#games-list article h2", "Another title")
  end

  test "adds a catalog game to the library", %{conn: conn} do
    game = game_fixture(%{title: "Pikmin 4"})
    {:ok, view, _html} = live(conn, "/catalogo")
    view |> element("#add-library-#{game.id}") |> render_click()
    assert %{game_id: game_id} = Library.get_entry_by_game(Accounts.default_owner(), game.id)
    assert game_id == game.id
  end
end
