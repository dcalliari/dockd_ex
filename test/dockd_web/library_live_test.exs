defmodule DockdWeb.LibraryLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Accounts
  alias Dockd.Library

  setup do
    game = game_fixture(%{title: "Kirby and the Forgotten Land"})
    %{game: game, user: Accounts.default_owner()}
  end

  test "lists only games marked Quero jogar", %{conn: conn, game: game, user: user} do
    {:ok, entry} = entry_fixture(user, game, %{purchase_intent: :want})
    other = game_fixture(%{title: "Not on the list"})

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#list-entry-#{entry.id}")
    assert has_element?(view, "#list-game-#{game.id}", "Kirby and the Forgotten Land")
    refute has_element?(view, "#list-game-#{other.id}")
    refute has_element?(view, "#library-tabs")
  end

  test "takes a game out of the list in place", %{conn: conn, game: game, user: user} do
    {:ok, entry} = entry_fixture(user, game, %{purchase_intent: :want})
    {:ok, view, _html} = live(conn, "/lista")

    view |> element("#remove-list-#{entry.id}") |> render_click()

    refute has_element?(view, "#list-entry-#{entry.id}")
    assert Library.get_entry!(user, entry.id).purchase_intent == :none
  end
end
