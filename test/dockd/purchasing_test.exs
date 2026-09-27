defmodule Dockd.PurchasingTest do
  use Dockd.DataCase
  alias Dockd.{Activity, Library, Purchasing}
  alias Dockd.Library.Shelf
  import Dockd.DomainFixtures

  setup do
    {:ok, user} = user_fixture(%{name: "Buyer"})
    game = game_fixture(%{title: "Wanted"})
    release = release_fixture(game)
    {:ok, _} = Library.set_status(user, game, :quero)
    %{user: user, game: game, release: release}
  end

  test "a purchase needs no price nor store", %{user: user, game: game, release: release} do
    assert {:ok, purchase} =
             Purchasing.create_purchase(user, %{
               release_id: release.id,
               format: :digital,
               purchased_at: DateTime.utc_now()
             })

    assert purchase.price_cents == nil
    assert purchase.retailer == nil
    assert Shelf.item(user, game).status == :backlog
  end

  test "undo brings back Quero and leaves no trace of the purchase",
       %{user: user, game: game, release: release} do
    events_before = Activity.list_events(user)
    {:ok, purchase} = purchase_fixture(user, release, %{price_cents: 7_990})
    assert Shelf.item(user, game).status == :backlog

    assert {:ok, _} = Purchasing.undo_purchase(user, purchase)

    item = Shelf.item(user, game)
    assert item.status == :quero
    assert item.ownerships == []
    assert Purchasing.list_purchases_for_game(user, game.id) == []
    assert Enum.map(Activity.list_events(user), & &1.id) == Enum.map(events_before, & &1.id)
  end

  test "undo refuses another user's purchase", %{user: user, release: release} do
    {:ok, purchase} = purchase_fixture(user, release)
    {:ok, other} = user_fixture(%{name: "Other"})
    assert {:error, :not_found} = Purchasing.undo_purchase(other, purchase)
  end

  test "month spending sums this month's prices and skips the ones without price",
       %{user: user, release: release} do
    other = release_fixture(game_fixture(%{title: "Older"}))
    another = release_fixture(game_fixture(%{title: "No price"}))

    {:ok, _} =
      purchase_fixture(user, release, %{
        price_cents: 7_990,
        purchased_at: ~U[2026-09-27 12:00:00Z]
      })

    {:ok, _} =
      purchase_fixture(user, other, %{price_cents: 5_000, purchased_at: ~U[2026-08-31 23:00:00Z]})

    {:ok, _} =
      purchase_fixture(user, another, %{price_cents: nil, purchased_at: ~U[2026-09-01 00:00:00Z]})

    assert Purchasing.month_spending(user, ~D[2026-09-15]) == 7_990
    assert Purchasing.month_spending(user, ~D[2026-10-01]) == 0
  end

  test "current price reads the latest observation, by media when asked",
       %{user: user, release: release} do
    observe(user, release, :physical, 39_900, -7200)
    observe(user, release, :digital, 34_900, -3600)

    assert %{price_cents: 34_900} = Purchasing.current_price(user, release.id)
    assert %{price_cents: 39_900} = Purchasing.current_price(user, release.id, :physical)
    assert %{price_cents: 34_900} = Purchasing.current_game_price(user, [release])
    assert Purchasing.current_game_price(user, [release_fixture(game_fixture())]) == nil
  end

  defp observe(user, release, format, cents, seconds) do
    {:ok, _} =
      Purchasing.create_price_observation(user, %{
        release_id: release.id,
        format: format,
        price_cents: cents,
        observed_at: DateTime.add(DateTime.utc_now(), seconds, :second),
        source: "eShop"
      })
  end
end
