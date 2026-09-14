defmodule DockdWeb.PageControllerTest do
  use DockdWeb.ConnCase

  test "GET / renders the planner", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert conn.status == 200
    assert conn.resp_body =~ "Planejador"
    assert conn.resp_body =~ ~s(id="igdb-attribution")
    assert conn.resp_body =~ ~s(href="https://www.igdb.com")
    assert conn.resp_body =~ ~s(rel="noopener noreferrer")
  end
end
