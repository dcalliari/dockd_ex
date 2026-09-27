defmodule DockdWeb.PlannerApiTest do
  use DockdWeb.ConnCase

  setup :register_api_user

  test "planner summary endpoint returns spending, calendar and backlog", %{conn: conn} do
    response = conn |> get("/api/v1/planner") |> json_response(200)
    assert Map.has_key?(response, "money")
    assert Map.has_key?(response, "calendar")
    assert Map.has_key?(response, "backlog")
    assert Map.has_key?(response, "recommendation")
  end
end
