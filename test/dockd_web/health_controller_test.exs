defmodule DockdWeb.HealthControllerTest do
  use DockdWeb.ConnCase

  test "reports application health", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
