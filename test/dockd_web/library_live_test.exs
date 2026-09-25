defmodule DockdWeb.LibraryLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.{Accounts, Library}

  setup do
    user = Accounts.default_owner()
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

  test "shows one derived status per game and the tab counts", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/")

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
    {:ok, view, _html} = live(conn, "/?tab=backlog")
    assert has_element?(view, "#shelf-#{ctx.owned.id}")
    refute has_element?(view, "#shelf-#{ctx.wanted.id}")

    view |> element("#filter-plat a", "Switch 2") |> render_click()
    assert_patch(view, "/?plat=switch_2&tab=backlog")
    assert has_element?(view, "#filter-plat.dk-filter--active summary b", "Switch 2")
    assert has_element?(view, "#library-empty", "Nada aqui.")

    {:ok, view, _html} = live(conn, "/?media=physical")
    assert has_element?(view, "#shelf-#{ctx.playing.id}")
    refute has_element?(view, "#shelf-#{ctx.owned.id}")
  end

  test "the navigation search always goes to Descobrir", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#nav-search-form[action='/descobrir']")
    refute has_element?(view, "#nav-search-form[phx-change]")
  end

  test "has no theme toggle and no sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    refute html =~ "phx:set-theme"
    refute html =~ "dockd-sidebar"
    assert html =~ ~s(class="dk-bottomnav")
  end
end
