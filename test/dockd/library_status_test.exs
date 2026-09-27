defmodule Dockd.LibraryStatusTest do
  use Dockd.DataCase, async: false
  import Dockd.DomainFixtures

  alias Dockd.{Activity, Library, Purchasing, Wallet}
  alias Dockd.Library.Shelf

  setup do
    {:ok, user} = user_fixture()
    game = game_fixture(%{title: "Pikmin 4"})
    release = release_fixture(game, %{platform: :switch, release_date: ~D[2023-07-21]})
    %{user: user, game: game, release: release}
  end

  test "nil takes the game out of the library", %{user: user, game: game} do
    {:ok, _} = Library.set_status(user, game, :jogando)
    assert Shelf.item(user, game).status == :jogando

    assert {:ok, :ok} = Library.set_status(user, game, nil)
    assert Shelf.item(user, game).status == nil
    assert Shelf.list(user) == []
  end

  test "nil on a game that is not there is harmless and logs nothing", %{user: user, game: game} do
    assert {:ok, :ok} = Library.set_status(user, game, nil)
    assert Activity.list_events(user) == []
  end

  test "nil keeps purchases, prices, wallet and events", %{user: user, game: game} = ctx do
    {:ok, _} = balance_fixture(user, %{amount_cents: 10_000})

    {:ok, _} =
      purchase_fixture(user, ctx.release, %{price_cents: 25_000, store_credit_used_cents: 4_000})

    {:ok, _} =
      Purchasing.create_price_observation(user, %{
        release_id: ctx.release.id,
        format: :digital,
        price_cents: 27_000,
        observed_at: DateTime.utc_now(),
        source: "eShop"
      })

    assert Shelf.item(user, game).status == :backlog
    events = length(Activity.list_events(user))

    {:ok, :ok} = Library.set_status(user, game, nil)

    assert Shelf.item(user, game).ownerships == []
    assert [%{price_cents: 25_000}] = Purchasing.list_purchases_for_game(user, game.id)
    assert %{price_cents: 27_000} = Purchasing.latest_price_observation(user, ctx.release.id)
    assert [%{amount_cents: 6_000}] = Wallet.list_balances(user)
    assert [%{type: :removed} | rest] = Activity.list_events(user)
    assert length(rest) == events
  end

  test "Backlog asks for ownership, then records it with the status",
       %{user: user, game: game} = ctx do
    assert {:error, :needs_ownership} = Library.set_status(user, game, :backlog)

    assert {:ok, _entry} =
             Library.set_status(user, game, :backlog,
               ownership: %{release_id: ctx.release.id, ownership_type: :physical}
             )

    item = Shelf.item(user, game)
    assert item.status == :backlog
    assert [%{ownership_type: :physical}] = item.ownerships
  end

  test "ownership only of a release of the same game", %{user: user, game: game} do
    other = release_fixture(game_fixture(%{title: "Other"}))

    assert {:error, :not_found} =
             Library.set_status(user, game, :backlog,
               ownership: %{release_id: other.id, ownership_type: :digital}
             )

    assert Shelf.item(user, game).status == nil
    assert Library.list_ownerships(user) == []
  end

  test "options never offer the current status, nor Quero once owned",
       %{user: user, game: game} = ctx do
    assert Library.status_options(Shelf.item(user, game)) == Shelf.statuses()

    {:ok, _} = Library.set_status(user, game, :quero)

    assert Library.status_options(Shelf.item(user, game)) == [
             :backlog,
             :jogando,
             :zerado,
             :larguei
           ]

    {:ok, _} =
      Library.set_status(user, game, :backlog,
        ownership: %{release_id: ctx.release.id, ownership_type: :digital}
      )

    {:ok, _} = Library.set_status(user, game, :jogando)
    assert Library.status_options(Shelf.item(user, game)) == [:backlog, :zerado, :larguei]
  end

  test "the first release is the one out first, undated last", %{game: game} = ctx do
    undated = release_fixture(game, %{platform: :switch_2, release_date: nil})
    later = release_fixture(game, %{platform: :switch_2, release_date: ~D[2025-06-05]})

    item = Shelf.item(nil, game)
    assert Shelf.first_release(item).id == ctx.release.id
    assert Shelf.first_release(%{item | releases: [undated, later]}).id == later.id
    assert Shelf.first_release(%{item | releases: []}) == nil
  end
end
