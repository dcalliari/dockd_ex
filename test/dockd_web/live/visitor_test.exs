defmodule DockdWeb.VisitorTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Library.{Entry, Ownership}
  alias Dockd.Repo

  setup do
    today = Date.utc_today()

    upcoming = game_fixture(%{title: "Visitor Upcoming", cover_url: "https://c/u.jpg"})
    release_fixture(upcoming, %{platform: :switch_2, release_date: Date.add(today, 20)})

    recent = game_fixture(%{title: "Visitor Recent"})
    release = release_fixture(recent, %{platform: :switch, release_date: Date.add(today, -10)})

    older = game_fixture(%{title: "Visitor Older"})
    release_fixture(older, %{platform: :switch, release_date: Date.add(today, -200)})

    %{upcoming: upcoming, recent: recent, release: release, older: older}
  end

  describe "a visitor" do
    test "opens on the catalog showcase, three strips and no library", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#showcase-lancamentos", "Próximos lançamentos")
      assert has_element?(view, "#strip-lancamentos #lancamentos-result-#{ctx.upcoming.id}")
      assert has_element?(view, "#strip-recentes #recentes-result-#{ctx.recent.id}")
      refute has_element?(view, "#strip-recentes #recentes-result-#{ctx.older.id}")
      assert has_element?(view, "#strip-em-alta #em-alta-result-#{ctx.older.id}")

      assert has_element?(
               view,
               "#showcase-recentes a[href='/descobrir?lista=recentes']",
               "Ver todos"
             )

      refute has_element?(view, "#library-tabs")
      refute has_element?(view, ".dk-bottomnav")
      assert has_element?(view, ".dk-nav__guest a[href='/criar-conta']", "Criar conta")
    end

    test "Ver todos opens Descobrir on that list", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/descobrir?lista=recentes")

      assert has_element?(view, "#discover-list", "Chegaram agora")
      assert has_element?(view, "#result-#{ctx.recent.id}")
      refute has_element?(view, "#result-#{ctx.upcoming.id}")
    end

    test "the status tag goes to Entrar and back to the same card", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/descobrir?q=visitor")

      volta = "/descobrir?abrir=result-#{ctx.upcoming.id}&q=visitor"
      href = ~p"/entrar?#{%{volta: volta}}"

      assert has_element?(view, "#result-#{ctx.upcoming.id} a.dk-status-menu[href='#{href}']")
      refute has_element?(view, "div.dk-status-menu")

      {:ok, entrar, _html} = live(conn, href)
      assert has_element?(entrar, "#entrar-form input[name=volta][value='#{volta}']")
    end

    test "saves nothing, even from a forged event", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/descobrir?q=visitor")
      render_hook(view, "set_status", %{"game_id" => ctx.upcoming.id, "status" => "quero"})

      {:ok, game, _html} = live(conn, ~p"/jogos/#{ctx.recent.id}")
      render_hook(game, "set_status", %{"status" => "quero"})
      render_hook(game, "own", %{"release_id" => ctx.release.id, "media" => "digital"})

      assert Repo.aggregate(Entry, :count) == 0
      assert Repo.aggregate(Ownership, :count) == 0
    end

    test "sees the game page as a catalog record", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.recent.id}")

      assert has_element?(view, "#game-hero h1", "Visitor Recent")
      assert has_element?(view, "#game-back[href='/descobrir']", "Descobrir")
      assert has_element?(view, "#release-#{ctx.release.id}", "Switch")
      refute has_element?(view, "#release-#{ctx.release.id}", "false")

      volta = "/jogos/#{ctx.recent.id}?abrir=status"

      assert has_element?(
               view,
               "#game-sign-in[href='#{~p"/entrar?#{%{volta: volta}}"}']",
               "+ Adicionar"
             )

      refute has_element?(view, "#game-status")
      refute has_element?(view, "#buy-button")
      refute has_element?(view, ".dk-row__end")
      refute has_element?(view, "#game-history")
    end

    test "Comprar asks for an account and comes back to it", %{conn: conn} do
      conn = get(conn, ~p"/comprar")

      assert redirected_to(conn) == ~p"/entrar"
      assert get_session(conn, :user_return_to) == "/comprar"
    end
  end

  describe "an account back from Entrar" do
    setup :register_and_log_in_user

    test "finds the menu of that card open, and it closes on a choice", %{conn: conn} = ctx do
      {:ok, view, _html} =
        live(conn, ~p"/descobrir?#{%{q: "visitor", abrir: "result-#{ctx.upcoming.id}"}}")

      assert has_element?(view, "#status-result-#{ctx.upcoming.id}.is-open[data-open=true]")
      refute has_element?(view, "#status-result-#{ctx.recent.id}.is-open")

      view
      |> element("#status-result-#{ctx.upcoming.id} button[phx-value-status=quero]")
      |> render_click()

      assert has_element?(view, "#result-#{ctx.upcoming.id}[data-status=quero]")
      refute has_element?(view, ".dk-status-menu.is-open")
    end

    test "finds the game page control open, and closing it keeps it closed",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/jogos/#{ctx.recent.id}?abrir=status")
      assert has_element?(view, "#game-status.is-open")

      render_hook(view, "close_status", %{})
      refute has_element?(view, "#game-status.is-open")
    end

    test "the home page shows the account rails", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ".dk-nav__link[aria-current=page]", "Início")
      refute has_element?(view, "#library-tabs")
      refute has_element?(view, "#strip-lancamentos")
      refute has_element?(view, ".dk-nav__guest")
    end

    test "Entrar goes straight to the page to come back to", %{conn: conn} = ctx do
      assert {:error, {:redirect, %{to: to}}} =
               live(conn, ~p"/entrar?#{%{volta: "/jogos/#{ctx.recent.id}"}}")

      assert to == "/jogos/#{ctx.recent.id}"
    end
  end
end
