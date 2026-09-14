defmodule DockdWeb.PageControllerTest do
  use DockdWeb.ConnCase

  test "GET / renders the planner", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert conn.status == 200
    assert conn.resp_body =~ "Planejador"
  end
end
