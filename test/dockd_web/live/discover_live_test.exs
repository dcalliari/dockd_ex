defmodule DockdWeb.DiscoverLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Library

  setup :register_and_log_in_user

  setup %{user: user} do
    candidate = game_fixture(%{title: "Discovery Candidate"})
    release_fixture(candidate, %{platform: :switch_2, release_date: ~D[2026-11-05]})

    listed = game_fixture(%{title: "Discovery Listed"})
    release_fixture(listed, %{platform: :switch, release_date: ~D[2024-01-01]})
    {:ok, _} = entry_fixture(user, listed, %{purchase_intent: :want})

    _other = game_fixture(%{title: "Something else"})
    %{user: user, candidate: candidate, listed: listed}
  end

  test "opens on upcoming releases and searches the catalog by title", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/descobrir")
    assert has_element?(view, "#discover-list", "Próximos lançamentos")
    assert has_element?(view, "#result-#{ctx.candidate.id}", "05/11/2026")
    refute has_element?(view, "#result-#{ctx.listed.id}")

    view |> form("#nav-search-form", %{"q" => "discovery"}) |> render_change()
    assert_patch(view, "/descobrir?q=discovery")

    assert has_element?(view, "#discover-count", "2 jogos para “discovery”")
    assert has_element?(view, "#result-#{ctx.candidate.id}")
    assert has_element?(view, "#result-#{ctx.listed.id}[data-status=quero]")
    refute has_element?(view, "#discover-results", "Something else")
  end

  test "the add chip sets a status in one tap", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/descobrir?q=candidate")
    assert has_element?(view, "#result-#{ctx.candidate.id} .dk-status--add")

    view
    |> element("#status-result-#{ctx.candidate.id} button[phx-value-status=quero]")
    |> render_click()

    assert %{purchase_intent: :want} = Library.get_entry_for_game(ctx.user, ctx.candidate.id)
    assert has_element?(view, "#result-#{ctx.candidate.id}[data-status=quero] .dk-status--quero")
    refute has_element?(view, "#result-#{ctx.candidate.id} .dk-status--add")
  end

  test "clicking the current tag takes the game out, in place", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/descobrir?q=listed")

    view |> element("#status-result-#{ctx.listed.id} .dk-status-menu__current") |> render_click()

    assert Library.get_entry_for_game(ctx.user, ctx.listed.id) == nil
    assert has_element?(view, "#result-#{ctx.listed.id}:not([data-status]) .dk-status--add")
  end

  test "Backlog without ownership asks the version on the card", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/descobrir?q=candidate")

    view
    |> element("#status-result-#{ctx.candidate.id} button[phx-value-status=backlog]")
    |> render_click()

    assert has_element?(view, "#status-result-#{ctx.candidate.id} .dk-status-menu__ask")

    view
    |> element(
      "#status-result-#{ctx.candidate.id} button[phx-click=own][phx-value-media=digital]"
    )
    |> render_click()

    assert has_element?(view, "#result-#{ctx.candidate.id}[data-status=backlog]")
    refute has_element?(view, "#status-result-#{ctx.candidate.id} button[phx-value-status=quero]")
  end

  test "the navigation search of other screens lands here", %{conn: conn} do
    conn = get(conn, "/descobrir", q: "else")
    assert html_response(conn, 200) =~ "Something else"
  end
end
