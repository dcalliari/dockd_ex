defmodule DockdWeb.GameLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Accounts
  alias Dockd.Library

  setup do
    game = game_fixture(%{title: "Metroid Prime 4"})
    release = release_fixture(game, %{platform: :switch, release_date: ~D[2027-01-01]})

    release_2 =
      release_fixture(game, %{
        platform: :switch_2,
        release_date: ~D[2027-12-31],
        release_date_precision: :year
      })

    %{game: game, release: release, release_2: release_2, user: Accounts.default_owner()}
  end

  test "returns to the route origin", %{conn: conn, game: game} do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{game.id}?from=list")

    assert has_element?(view, "#game-back[href='/']")
    assert has_element?(view, "#game-hero")
  end

  test "adds and removes the game from the list", %{conn: conn, game: game, user: user} do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{game.id}?from=catalog")

    view |> element("#add-to-list") |> render_click()
    assert has_element?(view, "#game-relation", "Na lista")
    assert Library.get_entry_for_game(user, game.id).purchase_intent == :want

    view |> element("#remove-from-list") |> render_click()
    refute has_element?(view, "#remove-from-list")
    assert Library.get_entry_for_game(user, game.id).purchase_intent == :none
  end

  test "shows platform and precise release dates", %{
    conn: conn,
    game: game,
    release: release,
    release_2: release_2
  } do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{game.id}")

    assert has_element?(view, "#game-platform", "Switch · Switch 2")
    assert has_element?(view, "#game-release-#{release.id}", "01/01/2027")
    assert has_element?(view, "#game-release-#{release_2.id}", "2027")
    refute has_element?(view, "#observation-form-#{release.id}")
  end
end
