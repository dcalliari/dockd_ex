defmodule DockdWeb.LibraryLiveTest do
  use DockdWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures
  alias Dockd.Accounts
  alias Dockd.Library

  setup do
    game = game_fixture(%{title: "Kirby and the Forgotten Land"})
    %{game: game}
  end

  test "lists entries and supports editing and removing", %{conn: conn, game: game} do
    user = Accounts.default_owner()
    {:ok, entry} = entry_fixture(user, game)
    {:ok, view, _html} = live(conn, "/biblioteca")

    assert has_element?(view, "#entry-#{entry.id}")
    view |> element("#edit-entry-#{entry.id}") |> render_click()
    assert has_element?(view, "#entry-form")
    view |> form("#entry-form", entry: %{backlog: "backlog", priority: "high"}) |> render_submit()
    assert Library.get_entry!(user, entry.id).backlog == :backlog
    view |> element("#remove-entry-#{entry.id}") |> render_click()
    refute has_element?(view, "#entry-#{entry.id}")
  end

  test "adds a game from the library", %{conn: conn, game: game} do
    {:ok, view, _html} = live(conn, "/biblioteca")
    view |> element("#add-game-#{game.id} button") |> render_click()

    assert has_element?(
             view,
             "#entry-" <>
               (Library.get_entry_by_game(Accounts.default_owner(), game.id) |> Map.fetch!(:id))
           )
  end
end
