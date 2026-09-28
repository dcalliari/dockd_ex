defmodule DockdWeb.LibraryLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Library
  alias Dockd.Library.Shelf

  setup :register_and_log_in_user

  setup %{user: user} do
    wanted = game_fixture(%{title: "Kirby and the Forgotten Land"})
    release_fixture(wanted, %{platform: :switch_2, release_date: ~D[2027-04-01]})
    {:ok, _} = entry_fixture(user, wanted, %{purchase_intent: :want})

    owned = game_fixture(%{title: "Hollow Knight"})
    owned_release = release_fixture(owned, %{platform: :switch, release_date: ~D[2018-06-12]})
    {:ok, _} = entry_fixture(user, owned, %{purchase_intent: :none})

    {:ok, _} =
      Library.create_ownership(user, %{
        release_id: owned_release.id,
        ownership_type: :digital,
        acquired_at: DateTime.utc_now()
      })

    playing = game_fixture(%{title: "Donkey Kong Bananza"})

    playing_release =
      release_fixture(playing, %{platform: :switch_2, release_date: ~D[2025-07-17]})

    {:ok, _} = entry_fixture(user, playing, %{purchase_intent: :none, play_state: :playing})

    {:ok, _} =
      Library.create_ownership(user, %{
        release_id: playing_release.id,
        ownership_type: :physical,
        acquired_at: DateTime.utc_now()
      })

    _browsed = game_fixture(%{title: "Never touched"})

    %{user: user, wanted: wanted, owned: owned, playing: playing}
  end

  test "an exclusive carries the game card on its cover", %{conn: conn} = ctx do
    multi = game_fixture(%{title: "Hades II", availability: :multiplatform})
    release_fixture(multi, %{platform: :switch, release_date: ~D[2025-09-25]})
    {:ok, _} = entry_fixture(ctx.user, multi, %{purchase_intent: :want})

    {:ok, view, _html} = live(conn, "/biblioteca")

    assert has_element?(view, "#shelf-#{ctx.wanted.id} .dk-poster .dk-exclusive--nintendo")
    refute has_element?(view, "#shelf-#{multi.id} .dk-exclusive")
  end

  test "shows one derived status per game and the tab counts", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/biblioteca")

    assert has_element?(view, "#shelf-#{ctx.wanted.id}[data-status=quero]")
    assert has_element?(view, "#shelf-#{ctx.owned.id}[data-status=backlog]")
    assert has_element?(view, "#shelf-#{ctx.playing.id}[data-status=jogando]")
    refute has_element?(view, "#library-grid", "Never touched")

    assert has_element?(view, "#library-tabs a[aria-selected=true]", "Todos")
    assert has_element?(view, "#library-tabs a", "Backlog 1")
    assert has_element?(view, "#library-tabs a", "Quero 1")
    assert has_element?(view, "#library-count", "3 jogos")
  end

  test "filters by tab, platform and media through the URL", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/biblioteca?tab=backlog")
    assert has_element?(view, "#shelf-#{ctx.owned.id}")
    refute has_element?(view, "#shelf-#{ctx.wanted.id}")

    view |> element("#filter-plat a", "Switch 2") |> render_click()
    assert_patch(view, "/biblioteca?plat=switch_2&tab=backlog")
    assert has_element?(view, "#filter-plat.dk-filter--active summary b", "Switch 2")
    assert has_element?(view, "#library-empty", "Nada aqui.")

    {:ok, view, _html} = live(conn, "/biblioteca?media=physical")
    assert has_element?(view, "#shelf-#{ctx.playing.id}")
    refute has_element?(view, "#shelf-#{ctx.owned.id}")
  end

  test "the account home separates current games from the library", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#home-playing", "Jogando agora")
    assert has_element?(view, "#home-playing-#{ctx.playing.id}[data-status=jogando]")
    assert has_element?(view, "#home-upcoming-#{ctx.wanted.id}[data-status=quero]")

    assert has_element?(
             view,
             "#home-upcoming-#{ctx.wanted.id} .dk-poster .dk-exclusive--nintendo"
           )

    assert has_element?(view, ".dk-nav__link[href='/biblioteca']", "Biblioteca")
    refute has_element?(view, "#library-tabs")
  end

  test "the navigation search always goes to Descobrir", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/biblioteca")

    assert has_element?(view, "#nav-search-form[action='/descobrir']")
    refute has_element?(view, "#nav-search-form[phx-change]")
  end

  test "has no theme toggle and no sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/biblioteca")

    refute html =~ "phx:set-theme"
    refute html =~ "dockd-sidebar"
    assert html =~ ~s(class="dk-bottomnav")
  end

  test "changes a status straight from the grid, and the card stays put", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/biblioteca?tab=backlog")

    view
    |> element("#status-#{ctx.owned.id} button[phx-value-status=jogando]")
    |> render_click()

    assert has_element?(view, "#shelf-#{ctx.owned.id}[data-status=jogando]")
    assert has_element?(view, "#library-tabs a", "Jogando 2")
    refute has_element?(view, "#status-#{ctx.owned.id} button[phx-value-status=quero]")

    refute has_element?(
             view,
             "#status-#{ctx.owned.id} .dk-status-menu__options .dk-status--jogando"
           )

    refute has_element?(view, "#shelf-#{ctx.wanted.id}")

    {:ok, view, _html} = live(conn, "/biblioteca")
    assert has_element?(view, "#status-#{ctx.wanted.id} button[phx-value-status=backlog]")

    refute has_element?(
             view,
             "#status-#{ctx.wanted.id} .dk-status-menu__options .dk-status--quero"
           )
  end

  test "clicking the current tag takes the game out, in place", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/biblioteca")
    refute has_element?(view, ".dk-card__trash")

    view |> element("#status-#{ctx.owned.id} .dk-status-menu__current") |> render_click()

    assert Shelf.item(ctx.user, ctx.owned).status == nil
    assert Library.get_entry_for_game(ctx.user, ctx.owned.id) == nil
    assert has_element?(view, "#shelf-#{ctx.owned.id}:not([data-status]) .dk-status--add")
    assert has_element?(view, "#library-tabs a", "Todos 2")
    assert has_element?(view, "#library-tabs a", "Backlog 0")

    view
    |> element("#status-#{ctx.owned.id} button[phx-value-status=quero]")
    |> render_click()

    assert has_element?(view, "#shelf-#{ctx.owned.id}[data-status=quero]")
    assert has_element?(view, "#library-tabs a", "Todos 3")

    view |> element("#library-tabs a", "Backlog") |> render_click()
    refute has_element?(view, "#shelf-#{ctx.owned.id}")
  end

  test "Backlog without ownership asks the version on the card", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/biblioteca")

    view
    |> element("#status-#{ctx.wanted.id} button[phx-value-status=backlog]")
    |> render_click()

    assert has_element?(
             view,
             "#status-#{ctx.wanted.id}.is-open .dk-status-menu__ask",
             "Tem em qual versão?"
           )

    refute has_element?(view, "#status-#{ctx.owned.id} .dk-status-menu__ask")

    view
    |> element("#status-#{ctx.wanted.id} button[phx-click=own][phx-value-media=physical]")
    |> render_click()

    assert has_element?(view, "#shelf-#{ctx.wanted.id}[data-status=backlog]")
    refute has_element?(view, ".dk-status-menu__ask")
    assert [%{ownership_type: :physical}] = Shelf.item(ctx.user, ctx.wanted).ownerships
  end
end
