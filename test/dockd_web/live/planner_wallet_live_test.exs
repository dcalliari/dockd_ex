defmodule DockdWeb.PlannerWalletLiveTest do
  use DockdWeb.ConnCase
  import Phoenix.LiveViewTest

  test "planner renders its primary sections", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#planner-money")
    assert has_element?(view, "#planner-calendar")
    assert has_element?(view, "#planner-backlog")
  end

  test "wallet renders balance and reservation forms", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/carteira")
    assert has_element?(view, "#balance-form")
    assert has_element?(view, "#reservation-form")
  end
end
