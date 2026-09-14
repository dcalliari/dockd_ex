defmodule Dockd.WalletTest do
  use Dockd.DataCase, async: true

  alias Dockd.Wallet

  test "creates a balance while ignoring unknown string keyed attributes" do
    {:ok, user} = Dockd.DomainFixtures.user_fixture()

    assert {:ok, balance} =
             Wallet.create_balance(user, %{
               "store" => "eshop",
               "amount_cents" => 1_000,
               "campo_inexistente" => "x"
             })

    assert balance.amount_cents == 1_000
    assert balance.store == :eshop
  end

  test "creates a reservation while ignoring unknown string keyed attributes" do
    {:ok, user} = Dockd.DomainFixtures.user_fixture()
    game = Dockd.DomainFixtures.game_fixture()

    assert {:ok, reservation} =
             Wallet.create_reservation(user, %{
               "store" => "eshop",
               "game_id" => game.id,
               "amount_cents" => 2_500,
               "note" => "Reserva",
               "campo_inexistente" => "x"
             })

    assert reservation.amount_cents == 2_500
    assert reservation.game_id == game.id
  end
end
