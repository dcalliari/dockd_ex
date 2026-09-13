defmodule DockdWeb.PageControllerTest do
  use DockdWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Catálogo"
  end
end
