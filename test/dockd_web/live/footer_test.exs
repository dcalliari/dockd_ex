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

    test "Sobre says what Dockd is and credits IGDB", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sobre")

      assert has_element?(view, "#about", "biblioteca pessoal de jogos")
      assert has_element?(view, "#about-credit a[href='https://www.igdb.com']", "IGDB")
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
