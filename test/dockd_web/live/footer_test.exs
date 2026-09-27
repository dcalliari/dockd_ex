defmodule DockdWeb.FooterTest do
  use DockdWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "a visitor" do
    test "sees the one-line footer on the catalog and Sobre", %{conn: conn} do
      for path <- ["/", "/descobrir", "/sobre"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "#site-footer .dk-wordmark--sm")
        assert has_element?(view, "#site-footer #footer-about[href='/sobre']", "Sobre")
        assert has_element?(view, "#site-footer a[href='https://www.igdb.com']", "IGDB")
        refute has_element?(view, "#site-footer.dk-footer--above-nav")
      end
    end

    test "Sobre says what Dockd is", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sobre")

      assert has_element?(view, "#about", "biblioteca pessoal de jogos")
    end

    test "credits IGDB once per screen, in the footer", %{conn: conn} do
      game =
        Dockd.DomainFixtures.game_fixture(%{
          title: "Credit Once",
          igdb_id: 77,
          slug: "credit-once"
        })

      for path <- ["/sobre", "/descobrir?q=credit", "/jogos/#{game.id}"] do
        {:ok, view, _html} = live(conn, path)
        text = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.text()
        text = String.replace(text, ~r/\s+/, " ")

        assert length(String.split(text, "Dados de jogos por IGDB")) == 2, path
      end
    end

    test "Entrar and Criar conta keep the covers without a footer", %{conn: conn} do
      for path <- ["/entrar", "/criar-conta"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "#entrar-backdrop")
        refute has_element?(view, "#site-footer")
      end
    end
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "the footer clears the phone bottom navigation", %{conn: conn} do
      for path <- ["/", "/comprar", "/sobre"] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, "#site-footer.dk-footer--above-nav")
      end
    end
  end
end
