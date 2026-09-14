defmodule Dockd.PlannerTest do
  use Dockd.DataCase
  alias Dockd.{Accounts, Catalog, Library, Planner, Wallet}
  import Dockd.DomainFixtures

  setup do
    {:ok, user} = Accounts.create_user(%{name: "Planner owner"})
    %{user: user}
  end

  test "summary calculates integer balance and reservations", %{user: user} do
    {:ok, _} = balance_fixture(user, %{amount_cents: 10_001, currency: "BRL"})
    game = game_fixture()

    {:ok, _} =
      Wallet.create_reservation(user, %{store: :eshop, game_id: game.id, amount_cents: 2_501})

    money = Planner.summary(user).money
    assert money.balance_cents == 10_001
    assert money.reserved_cents == 2_501
    assert money.free_cents == 7_500
    assert money.currency == "BRL"
  end

  test "calendar recommends reserving exclusives and waiting on multiplatform games", %{
    user: user
  } do
    exclusive = game_fixture(%{title: "Exclusive recommendation"})
    multi = game_fixture(%{title: "Multiplatform recommendation", availability: :multiplatform})

    {:ok, _} =
      Catalog.create_release(exclusive.id, %{platform: :switch, release_date: ~D[2026-12-01]})

    {:ok, _} =
      Catalog.create_release(multi.id, %{platform: :switch, release_date: ~D[2026-12-02]})

    {:ok, _} = Library.create_entry(user, %{game_id: exclusive.id, purchase_intent: :want})
    {:ok, _} = Library.create_entry(user, %{game_id: multi.id, purchase_intent: :want})

    assert Enum.map(Planner.upcoming_releases(user, ~D[2026-01-01]), & &1.recommendation) == [
             "reserve",
             "can_wait"
           ]
  end

  test "calendar excludes vetoed releases and labels availability", %{user: user} do
    exclusive = game_fixture(%{title: "Exclusive"})
    multi = game_fixture(%{title: "Multi", availability: :multiplatform})

    {:ok, r1} =
      Catalog.create_release(exclusive.id, %{platform: :switch, release_date: ~D[2026-12-01]})

    {:ok, _r2} =
      Catalog.create_release(multi.id, %{platform: :switch, release_date: ~D[2026-12-02]})

    {:ok, _} = Library.create_entry(user, %{game_id: exclusive.id, purchase_intent: :want})
    {:ok, _} = Library.create_entry(user, %{game_id: multi.id, purchase_intent: :want})
    {:ok, _} = Library.create_veto(user, %{release_id: r1.id, reason: "PC"})
    calendar = Planner.upcoming_releases(user, ~D[2026-01-01])
    assert Enum.map(calendar, & &1.recommendation) == ["can_wait"]
  end

  test "backlog is ordered by oldest event", %{user: user} do
    old = game_fixture(%{title: "Old"})
    new = game_fixture(%{title: "New"})
    {:ok, _} = Library.create_entry(user, %{game_id: old.id, backlog: :backlog})
    {:ok, _} = Library.create_entry(user, %{game_id: new.id, backlog: :backlog})
    assert Enum.map(Planner.backlog(user), & &1.game.title) == ["Old", "New"]
  end
end
