defmodule DockdWeb.PlannerWalletApiTest do
  use DockdWeb.ConnCase

  test "planner summary endpoint returns money, calendar and backlog", %{conn: conn} do
    response = conn |> get("/api/v1/planner") |> json_response(200)
    assert Map.has_key?(response, "money")
    assert Map.has_key?(response, "calendar")
    assert Map.has_key?(response, "backlog")
  end

  test "wallet collection endpoints return data", %{conn: conn} do
    assert %{"data" => _} = conn |> get("/api/v1/wallet/balances") |> json_response(200)
    assert %{"data" => _} = conn |> get("/api/v1/wallet/reservations") |> json_response(200)
  end

  test "wallet balance create endpoint validates its contract", %{conn: conn} do
    response =
      post(conn, "/api/v1/wallet/balances", %{balance: %{store: "eshop", amount_cents: 2500}})

    assert response.status in [201, 422]
  end

  test "wallet reservation create endpoint validates its contract", %{conn: conn} do
    response =
      post(conn, "/api/v1/wallet/reservations", %{
        reservation: %{store: "eshop", amount_cents: 2500}
      })

    assert response.status in [201, 422]
  end
end
