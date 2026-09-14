defmodule Dockd.DomainTest do
  use Dockd.DataCase, async: false
  import Dockd.DomainFixtures
  alias Dockd.{Accounts, Activity, Library, Purchasing, Wallet}
  alias Dockd.Activity.Event

  setup do
    {:ok, user} = user_fixture()
    {:ok, other} = user_fixture(%{name: "Other"})
    game = game_fixture()
    release = release_fixture(game)
    %{user: user, other: other, game: game, release: release}
  end

  test "entries are scoped and state changes emit one event", %{
    user: user,
    other: other,
    game: game
  } do
    {:ok, entry} = Library.create_entry(user, %{game_id: game.id})
    assert [listed] = Library.list_entries(user)
    assert listed.id == entry.id
    assert Library.list_entries(other) == []
    assert {:error, :not_found} = Library.update_entry(other, listed, %{backlog: :backlog})
    assert {:ok, _} = Library.update_entry(user, listed, %{backlog: :backlog})

    assert [%Event{type: :backlogged}] =
             Activity.list_events(user) |> Enum.filter(&(&1.type == :backlogged))
  end

  test "uniqueness and money validation", %{user: user, game: game, release: release} do
    assert {:ok, _} = Library.create_entry(user, %{game_id: game.id})
    assert {:error, changeset} = Library.create_entry(user, %{game_id: game.id})
    assert changeset.errors[:user_id]

    assert {:error, changeset} =
             Purchasing.create_price_observation(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: -1,
               observed_at: DateTime.utc_now(),
               source: "test"
             })

    assert changeset.errors[:price_cents]

    assert {:ok, _} =
             Wallet.create_balance(user, %{store: :eshop, amount_cents: 10, currency: "BRL"})

    assert {:error, changeset} = Wallet.create_balance(user, %{store: :eshop, amount_cents: 10})
    assert changeset.errors[:user_id]

    assert {:ok, ownership} =
             Library.create_ownership(user, %{
               release_id: release.id,
               ownership_type: :digital,
               acquired_at: DateTime.utc_now()
             })

    assert {:error, changeset} =
             Library.create_ownership(user, %{
               release_id: release.id,
               ownership_type: :digital,
               acquired_at: DateTime.utc_now()
             })

    assert changeset.errors[:user_id]
    assert {:ok, veto} = Library.create_veto(user, %{release_id: release.id})
    assert {:error, changeset} = Library.create_veto(user, %{release_id: release.id})
    assert changeset.errors[:user_id]
    assert {:ok, _} = Library.delete_ownership(user, ownership)
    assert {:ok, _} = Library.delete_veto(user, veto)
  end

  test "purchase ownership failure rolls back purchase and event", %{user: user, release: release} do
    assert {:ok, _} =
             Library.create_ownership(user, %{
               release_id: release.id,
               ownership_type: :digital,
               acquired_at: DateTime.utc_now()
             })

    assert {:error, changeset} =
             Purchasing.create_purchase(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: 100,
               purchased_at: DateTime.utc_now(),
               retailer: "eShop"
             })

    assert changeset.errors[:user_id]
    assert Purchasing.list_purchases(user, release.id) == []
    refute Enum.any?(Activity.list_events(user), &(&1.type == :purchased))
  end

  test "purchase and veto append their event atomically", %{user: user, release: release} do
    assert {:ok, _} =
             Purchasing.create_purchase(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: 100,
               purchased_at: DateTime.utc_now(),
               retailer: "eShop"
             })

    assert Enum.any?(Activity.list_events(user), &(&1.type == :purchased))
    assert {:error, _} = Library.create_veto(user, %{release_id: Ecto.UUID.generate()})
    refute Enum.any?(Activity.list_events(user), &(&1.type == :vetoed))
  end

  test "queries return game entry, release veto, latest observation, and purchases", %{
    user: user,
    game: game,
    release: release
  } do
    assert {:ok, entry} = Library.create_entry(user, %{game_id: game.id})
    assert Library.get_entry_for_game(user, game.id).id == entry.id
    assert Library.get_entry_for_game(user, Ecto.UUID.generate()) == nil

    assert {:ok, veto} = Library.create_veto(user, %{release_id: release.id, reason: "PC first"})
    assert Library.get_veto_for_release(user, release.id).id == veto.id

    old = DateTime.add(DateTime.utc_now(), -1, :hour)

    assert {:ok, first} =
             Purchasing.create_price_observation(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: 100,
               observed_at: old,
               source: "eShop"
             })

    assert {:ok, second} =
             Purchasing.create_price_observation(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: 90,
               observed_at: DateTime.utc_now(),
               source: "eShop"
             })

    assert Purchasing.latest_price_observation(user, release.id).id == second.id

    assert Purchasing.list_price_observations(user, release.id) |> Enum.map(& &1.id) == [
             second.id,
             first.id
           ]

    assert {:ok, purchase} = purchase_fixture(user, release)
    assert [listed] = Purchasing.list_purchases(user, release.id)
    assert listed.id == purchase.id
  end

  test "default owner is idempotent and stale observations use seven days", %{
    user: user,
    release: release
  } do
    assert Accounts.default_owner().id == Accounts.default_owner().id
    old = DateTime.add(DateTime.utc_now(), -8, :day)

    {:ok, observation} =
      Purchasing.create_price_observation(user, %{
        release_id: release.id,
        format: :digital,
        price_cents: 100,
        observed_at: old,
        source: "test"
      })

    refute Purchasing.stale?(observation, old, 7)
    assert Purchasing.stale?(observation, DateTime.utc_now())
  end
end
