defmodule DockdWeb.GameLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.{Library, Purchasing}
  alias Dockd.Library.Shelf

  setup :register_and_log_in_user

  setup do
    game = game_fixture(%{title: "Metroid Prime 4", developer: "Retro Studios"})
    release = release_fixture(game, %{platform: :switch, release_date: ~D[2027-01-01]})

    release_2 =
      release_fixture(game, %{
        platform: :switch_2,
        release_date: ~D[2027-12-31],
        release_date_precision: :year
      })

    %{game: game, release: release, release_2: release_2}
  end

  test "shows the hero, the caption and the versions", %{conn: conn} = ctx do
    {:ok, view, html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    assert has_element?(view, "#game-back[href='/']")
    assert has_element?(view, "#game-hero h1", "Metroid Prime 4")
    assert has_element?(view, "#game-meta", "Retro Studios · 2027")
    assert html =~ "Exclusivo"
    assert has_element?(view, "#release-#{ctx.release.id} .dk-date b", "01")
    assert has_element?(view, "#release-#{ctx.release_2.id} .dk-date--year b", "2027")
    refute html =~ "Edição padrão"
  end

  test "sets Quero, then Jogando, through the status control", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("button.dk-status--quero[phx-click=set_status]") |> render_click()
    assert Shelf.item(ctx.user, ctx.game).status == :quero
    assert has_element?(view, "#buy-button", "Comprei")

    view |> element("button.dk-status--jogando[phx-click=set_status]") |> render_click()
    assert Shelf.item(ctx.user, ctx.game).status == :jogando
    assert Library.get_entry_for_game(ctx.user, ctx.game.id).play_state == :playing
    assert has_element?(view, "#game-history", "Começou a jogar")
  end

  test "Backlog without ownership asks the version and media first", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("button.dk-status--backlog[phx-click=set_status]") |> render_click()
    assert has_element?(view, "#own-panel", "Tem em qual versão?")

    view
    |> element(
      "#own-panel button[phx-value-release_id='#{ctx.release.id}'][phx-value-media=physical]"
    )
    |> render_click()

    item = Shelf.item(ctx.user, ctx.game)
    assert item.status == :backlog
    assert [%{ownership_type: :physical}] = item.ownerships
    assert has_element?(view, "#release-#{ctx.release.id}", "Tem")
    refute has_element?(view, "button.dk-status--quero[phx-click=set_status]")
  end

  test "registers an observed price inline", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("#release-#{ctx.release.id} button", "Registrar preço") |> render_click()

    view
    |> form("#price-form-#{ctx.release.id}", %{"price" => "349,90", "source" => "OLX"})
    |> render_submit()

    assert %{price_cents: 34_990, source: "OLX"} =
             Purchasing.latest_price_observation(ctx.user, ctx.release.id)

    assert has_element?(view, "#price-#{ctx.release.id}", "R$ 349,90")
    assert has_element?(view, "#game-history", "Viu o preço: R$ 349,90")
  end

  test "Comprei records the purchase and turns the game into Backlog", %{conn: conn} = ctx do
    {:ok, _} = entry_fixture(ctx.user, ctx.game, %{purchase_intent: :want})
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("#buy-button") |> render_click()
    view |> form("#buy-form-#{ctx.release.id}", %{"price" => "299,90"}) |> render_submit()

    item = Shelf.item(ctx.user, ctx.game)
    assert item.status == :backlog
    assert [%{price_cents: 29_990}] = Purchasing.list_purchases_for_game(ctx.user, ctx.game.id)
    assert has_element?(view, "#game-history", "Comprou")
  end
end
