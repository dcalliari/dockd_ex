defmodule DockdWeb.DiscoverLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.{Accounts, Library}

  setup do
    user = Accounts.default_owner()
    candidate = game_fixture(%{title: "Discovery Candidate"})
    release_fixture(candidate, %{platform: :switch_2, release_date: ~D[2026-11-05]})

    listed = game_fixture(%{title: "Discovery Listed"})
    release_fixture(listed, %{platform: :switch, release_date: ~D[2024-01-01]})
    {:ok, _} = entry_fixture(user, listed, %{purchase_intent: :want})

    _other = game_fixture(%{title: "Something else"})
    %{user: user, candidate: candidate, listed: listed}
  end

  test "starts empty and searches the catalog by title", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/descobrir")
    assert has_element?(view, "#discover-hint")

    view |> form("#nav-search-form", %{"q" => "discovery"}) |> render_change()
    assert_patch(view, "/descobrir?q=discovery")

    assert has_element?(view, "#discover-count", "2 jogos para “discovery”")
    assert has_element?(view, "#result-#{ctx.candidate.id}")
    assert has_element?(view, "#result-#{ctx.listed.id}[data-status=quero]")
    refute has_element?(view, "#discover-results", "Something else")
  end

  test "Quero jogar adds the game in one tap and becomes the chip", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/descobrir?q=candidate")

    view
    |> element("#result-#{ctx.candidate.id} .dk-poster__veil button", "Quero jogar")
    |> render_click()

    assert %{purchase_intent: :want} = Library.get_entry_for_game(ctx.user, ctx.candidate.id)
    assert has_element?(view, "#result-#{ctx.candidate.id}[data-status=quero] .dk-status--quero")
    refute has_element?(view, "#result-#{ctx.candidate.id} button.discover-want")
  end

  test "the navigation search of other screens lands here", %{conn: conn} do
    conn = get(conn, "/descobrir", q: "else")
    assert html_response(conn, 200) =~ "Something else"
  end
end
