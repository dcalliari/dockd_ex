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

    assert has_element?(view, "#game-back[href='/biblioteca']")
    assert has_element?(view, "#game-hero h1", "Metroid Prime 4")
    assert has_element?(view, "#game-meta", "Retro Studios · 2027")
    assert has_element?(view, "#game-hero .dk-poster .dk-exclusive--nintendo")
    refute has_element?(view, "#game-hero .dk-poster-caption", "Exclusivo")
    assert has_element?(view, "#release-#{ctx.release.id} .dk-date b", "01")
    assert has_element?(view, "#release-#{ctx.release_2.id} .dk-date--year b", "2027")
    refute html =~ "Edição padrão"
  end

  test "a version the eShop has not released says so", %{conn: conn} = ctx do
    store_price_fixture(ctx.release_2, %{sales_status: "unreleased", regular_cents: nil})
    store_price_fixture(ctx.release, %{sales_status: "preorder"})
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    assert has_element?(view, "#release-#{ctx.release_2.id} .dk-row__meta", "não lançado")
    assert has_element?(view, "#release-#{ctx.release.id} .dk-row__meta", "pré-venda")
  end

  describe "Versões with editions" do
    setup ctx do
      store_price_fixture(ctx.release, %{regular_cents: 29_990})

      editions =
        for {name, cents} <- [{"Deluxe", 34_990}, {"Premium", 44_450}, {"Ouro", 31_000}],
            into: %{} do
          release = release_fixture(ctx.game, %{platform: :switch, edition: name})
          store_price_fixture(release, %{regular_cents: cents})
          {name, release}
        end

      unsold = release_fixture(ctx.game, %{platform: :switch, edition: "Colecionador"})
      %{editions: editions, unsold: unsold}
    end

    test "sit under their platform, the two cheapest first, without a count",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")
      version = "#release-#{ctx.release.id}"

      refute has_element?(view, ".dk-section h2 span")
      assert has_element?(view, "#{version} > .dk-row .dk-row__title", "Switch")

      assert has_element?(
               view,
               "#{version} .dk-editions #release-#{ctx.editions["Ouro"].id}",
               "R$ 310,00"
             )

      assert has_element?(
               view,
               "#{version} .dk-editions #release-#{ctx.editions["Deluxe"].id}",
               "Pacote · Digital"
             )

      refute has_element?(view, "#release-#{ctx.editions["Premium"].id}")
      refute has_element?(view, "#release-#{ctx.unsold.id}")

      view |> element("#editions-switch", "Mais 1 edição") |> render_click()
      assert has_element?(view, "#release-#{ctx.editions["Premium"].id}", "R$ 444,50")

      view |> element("#editions-switch", "Menos edições") |> render_click()
      refute has_element?(view, "#release-#{ctx.editions["Premium"].id}")
    end

    test "an owned edition always shows, and says so", %{conn: conn} = ctx do
      {:ok, _} = purchase_fixture(ctx.user, ctx.unsold)
      {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

      assert has_element?(view, "#release-#{ctx.unsold.id}", "Colecionador")
      assert has_element?(view, "#release-#{ctx.unsold.id} .dk-row__meta", "Tem")
    end

    test "a standard edition the store stopped selling says so", %{conn: conn} = ctx do
      store_price_fixture(ctx.release_2, %{regular_cents: nil, sales_status: "sales_termination"})
      {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

      assert has_element?(view, "#release-#{ctx.release_2.id} .dk-row__meta", "fora de venda")
      assert has_element?(view, "#price-#{ctx.release_2.id}", "Sem preço")
    end

    test "Comprei opens the choices under the hero, each with its price", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")
      view |> element("#buy-button") |> render_click()

      options = "#buy-options"
      ouro = "#{options}-#{ctx.editions["Ouro"].id}-digital"
      assert has_element?(view, "#{options}-#{ctx.release.id}-digital", "Edição padrão")
      assert has_element?(view, "#{options}-#{ctx.release.id}-digital", "R$ 299,90")
      assert has_element?(view, ouro, "Switch · Digital")
      refute has_element?(view, "#{options}-#{ctx.editions["Premium"].id}-digital")
      refute has_element?(view, "#{options}-#{ctx.unsold.id}-digital")

      view |> element("#{options}-more", "Mais 1 edição") |> render_click()
      assert has_element?(view, "#{options}-#{ctx.editions["Premium"].id}-digital")

      view |> element("#{ouro} button", "Comprei esta") |> render_click()

      refute has_element?(view, options)
      assert [purchase] = Purchasing.list_purchases_for_game(ctx.user, ctx.game.id)
      assert purchase.release_id == ctx.editions["Ouro"].id
      assert purchase.price_cents == 31_000
      assert Shelf.item(ctx.user, ctx.game).status == :backlog
    end

    test "Cancelar closes the choices", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")
      view |> element("#buy-button") |> render_click()
      view |> element("#buy-options button", "Cancelar") |> render_click()

      refute has_element?(view, "#buy-options")
      assert Purchasing.list_purchases_for_game(ctx.user, ctx.game.id) == []
    end
  end

  test "links to the game's IGDB page without repeating the credit", %{conn: conn} = ctx do
    {:ok, game} = Dockd.Catalog.update_game(ctx.game, %{igdb_id: 4242, slug: "metroid-prime-4"})
    {:ok, view, _html} = live(conn, ~p"/jogos/#{game.id}")

    assert has_element?(
             view,
             "#game-igdb a[href='https://www.igdb.com/games/metroid-prime-4']",
             "Mais informações no IGDB"
           )

    refute has_element?(view, "#game-igdb", "Dados de jogos por")
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

  test "Backlog without ownership asks the version and media in the control",
       %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("button.dk-status--backlog[phx-click=set_status]") |> render_click()
    assert has_element?(view, "#game-status.is-open .dk-status-menu__ask", "Tem em qual versão?")
    assert has_element?(view, "#game-status button[phx-click=own]", "Switch 2 · Físico")

    view
    |> element(
      "#game-status button[phx-value-release_id='#{ctx.release.id}'][phx-value-media=physical]"
    )
    |> render_click()

    item = Shelf.item(ctx.user, ctx.game)
    assert item.status == :backlog
    assert [%{ownership_type: :physical}] = item.ownerships
    assert has_element?(view, "#release-#{ctx.release.id}", "Tem")
    refute has_element?(view, "#game-status.is-open")
    refute has_element?(view, "button.dk-status--quero[phx-click=set_status]")
  end

  test "Cancelar closes the version question and saves nothing", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("button.dk-status--backlog[phx-click=set_status]") |> render_click()
    view |> element("#game-status button", "Cancelar") |> render_click()

    refute has_element?(view, ".dk-status-menu__ask")
    assert Shelf.item(ctx.user, ctx.game).status == nil
  end

  test "clicking the current tag takes the game out and keeps what it cost",
       %{conn: conn} = ctx do
    {:ok, _} = entry_fixture(ctx.user, ctx.game, %{purchase_intent: :want})
    {:ok, _} = purchase_fixture(ctx.user, ctx.release, %{price_cents: 29_990})

    {:ok, _} =
      Purchasing.create_price_observation(ctx.user, %{
        release_id: ctx.release.id,
        format: :digital,
        price_cents: 31_990,
        observed_at: DateTime.utc_now(),
        source: "eShop"
      })

    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")
    refute has_element?(view, "#remove-game")
    assert has_element?(view, "#game-status .dk-status-menu__current .dk-status--backlog")

    view |> element("#game-status .dk-status-menu__current") |> render_click()

    item = Shelf.item(ctx.user, ctx.game)
    assert item.status == nil
    assert item.ownerships == []
    assert [%{price_cents: 29_990}] = Purchasing.list_purchases_for_game(ctx.user, ctx.game.id)
    assert %{price_cents: 31_990} = Purchasing.latest_price_observation(ctx.user, ctx.release.id)

    assert has_element?(view, "#game-status .dk-status--add", "+ Adicionar")
    assert has_element?(view, "#game-history", "Comprou")
    assert has_element?(view, "#game-history", "Viu o preço: R$ 319,90")
    assert has_element?(view, "#game-history .dk-history__item--current", "Saiu da biblioteca")
  end

  test "a version sold on the eShop shows the store price", %{conn: conn} = ctx do
    store_price_fixture(ctx.release_2, %{regular_cents: 43_990})
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    assert has_element?(view, "#price-#{ctx.release_2.id}", "R$ 439,90")
    assert has_element?(view, "#price-#{ctx.release_2.id}", "menor preço desde")
    refute has_element?(view, "#price-#{ctx.release.id}", "menor preço desde")
  end

  test "a promotion that is also the lowest price ever seen shows both marks together",
       %{conn: conn} = ctx do
    now = DateTime.utc_now()

    store_price_fixture(ctx.release_2, %{
      regular_cents: 15_990,
      discount_cents: 3_997,
      discount_starts_at: DateTime.add(now, -1, :day),
      discount_ends_at: DateTime.add(now, 5, :day)
    })

    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")
    ends_at = DateTime.add(now, 5, :day) |> Calendar.strftime("%d/%m")

    assert has_element?(view, "#price-#{ctx.release_2.id} s", "R$ 159,90")
    assert has_element?(view, "#price-#{ctx.release_2.id} b", "R$ 39,97")
    assert has_element?(view, "#price-#{ctx.release_2.id}", "até #{ends_at} · menor preço")
  end

  test "the price opens the manual record in place", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("#price-#{ctx.release.id}", "Sem preço") |> render_click()
    view |> form("#price-form-#{ctx.release.id}", %{"price" => "abc"}) |> render_submit()
    assert has_element?(view, "#price-form-#{ctx.release.id} .dk-field__error", "Use 199,90")

    view
    |> form("#price-form-#{ctx.release.id}", %{"price" => "349,90", "source" => "OLX"})
    |> render_submit()

    assert %{price_cents: 34_990, source: "OLX"} =
             Purchasing.latest_price_observation(ctx.user, ctx.release.id)

    assert has_element?(view, "#price-#{ctx.release.id}", "R$ 349,90")
    assert has_element?(view, "#game-history", "Viu o preço: R$ 349,90")

    view |> element("#price-#{ctx.release.id}") |> render_click()
    assert has_element?(view, "#price-form-#{ctx.release.id} .dk-seen", "R$ 349,90")
  end

  test "Comprei asks the version, buys it with the price seen, and Desfazer undoes it",
       %{conn: conn} = ctx do
    {:ok, _} = entry_fixture(ctx.user, ctx.game, %{purchase_intent: :want})

    {:ok, _} =
      Purchasing.create_price_observation(ctx.user, %{
        release_id: ctx.release_2.id,
        format: :digital,
        price_cents: 29_990,
        observed_at: DateTime.utc_now(),
        source: "eShop"
      })

    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("#buy-button") |> render_click()
    assert Purchasing.list_purchases_for_game(ctx.user, ctx.game.id) == []
    view |> element("#buy .dk-choice button", "Switch 2") |> render_click()

    item = Shelf.item(ctx.user, ctx.game)
    assert item.status == :backlog
    assert [%{release_id: release_id}] = item.ownerships
    assert release_id == ctx.release_2.id
    assert [%{price_cents: 29_990}] = Purchasing.list_purchases_for_game(ctx.user, ctx.game.id)
    assert has_element?(view, "#game-history .dk-history__item--current", "Comprou: R$ 299,90")
    refute has_element?(view, "#game-history", "Registrou a posse")
    assert has_element?(view, "#release-#{ctx.release_2.id}", "pagou R$ 299,90")

    view |> element("#buy button", "Desfazer") |> render_click()

    assert Shelf.item(ctx.user, ctx.game).status == :quero
    assert Purchasing.list_purchases_for_game(ctx.user, ctx.game.id) == []
    refute has_element?(view, "#game-history", "Comprou")
    assert has_element?(view, "#buy-button", "Comprei")
  end

  test "Cancelar closes the version question and buys nothing", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.game.id}")

    view |> element("#buy-button") |> render_click()
    view |> element("#buy button", "Cancelar") |> render_click()

    assert has_element?(view, "#buy-button")
    assert Purchasing.list_purchases_for_game(ctx.user, ctx.game.id) == []
  end
end
