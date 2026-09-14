defmodule DockdWeb.PageControllerTest do
  use DockdWeb.ConnCase

  test "GET / redirects to the catalog", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/catalogo"
  end
end
