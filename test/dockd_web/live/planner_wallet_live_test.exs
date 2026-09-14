defmodule DockdWeb.PlannerWalletLiveTest do
  use DockdWeb.ConnCase
  import Phoenix.LiveViewTest

  test "planner renders empty states with useful links", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#planner-money")
    assert has_element?(view, "#planner-calendar")
    assert has_element?(view, "#planner-calendar a[href='/catalogo']")
    assert has_element?(view, "#planner-backlog")
    assert has_element?(view, "#planner-backlog a[href='/biblioteca']")
  end

  test "wallet creates edits and deletes a reservation and edits balance", %{conn: conn} do
    game = Dockd.DomainFixtures.game_fixture(%{title: "Reserved game"})
    user = Dockd.Accounts.default_owner()
    {:ok, view, _html} = live(conn, "/carteira")

    view
    |> form("#balance-form", store_balance: %{amount_cents: "123,45", currency: "BRL"})
    |> render_submit()

    assert Dockd.Wallet.get_balance(user, :eshop).amount_cents == 12_345

    view |> element("#new-reservation-button") |> render_click()

    view
    |> form("#reservation-form",
      balance_reservation: %{game_id: game.id, amount_cents: "50,00", note: "Teste"}
    )
    |> render_submit()

    [reservation] = Dockd.Wallet.list_reservations(user)
    assert reservation.amount_cents == 5_000
    assert has_element?(view, "#reservation-#{reservation.id}")

    view |> element("#reservation-#{reservation.id} button", "Editar") |> render_click()

    view
    |> form("#reservation-form",
      balance_reservation: %{game_id: game.id, amount_cents: "60,00", note: "Atualizada"}
    )
    |> render_submit()

    assert Dockd.Wallet.get_reservation!(user, reservation.id).amount_cents == 6_000

    view |> element("#reservation-#{reservation.id} button", "Excluir") |> render_click()
    refute has_element?(view, "#reservation-#{reservation.id}")
  end
end
