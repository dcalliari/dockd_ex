defmodule Dockd.LibraryStatusTest do
  use Dockd.DataCase, async: false
  import Dockd.DomainFixtures

  alias Dockd.{Activity, Library, Purchasing}
  alias Dockd.Library.Shelf

  setup do
    {:ok, user} = user_fixture()
    game = game_fixture(%{title: "Pikmin 4"})
    release = release_fixture(game, %{platform: :switch, release_date: ~D[2023-07-21]})
    %{user: user, game: game, release: release}
  end

  test "nil takes the game out of the library", %{user: user, game: game} = ctx do
    {:ok, _} =
      Library.set_status(user, game, :jogando,
        ownership: %{release_id: ctx.release.id, ownership_type: :digital}
      )

    assert Shelf.item(user, game).status == :jogando

    assert {:ok, :ok} = Library.set_status(user, game, nil)
    assert Shelf.item(user, game).status == nil
    assert Shelf.list(user) == []
  end

  test "nil on a game that is not there is harmless and logs nothing", %{user: user, game: game} do
    assert {:ok, :ok} = Library.set_status(user, game, nil)
    assert Activity.list_events(user) == []
  end

  test "nil keeps purchases, prices and events", %{user: user, game: game} = ctx do
    {:ok, _} = purchase_fixture(user, ctx.release, %{price_cents: 25_000})

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

  test "Jogando, Pausado, Zerado and Larguei also ask for ownership",
       %{user: user, game: game} = ctx do
    for status <- [:jogando, :pausado, :zerado, :larguei] do
      assert {:error, :needs_ownership} = Library.set_status(user, game, status)
    end

    assert {:ok, _entry} =
             Library.set_status(user, game, :pausado,
               ownership: %{release_id: ctx.release.id, ownership_type: :digital}
             )

    item = Shelf.item(user, game)
    assert item.status == :pausado
    assert [%{ownership_type: :digital}] = item.ownerships

    # Owning the release already covers every later transition.
    assert {:ok, _} = Library.set_status(user, game, :zerado)
    assert Shelf.item(user, game).status == :zerado
  end

  test "Joguei em outro lugar records owned_elsewhere instead of a release",
       %{user: user, game: game} do
    assert {:ok, _entry} = Library.set_status(user, game, :jogando, owned_elsewhere: true)

    item = Shelf.item(user, game)
    assert item.status == :jogando
    assert item.ownerships == []
    assert item.entry.owned_elsewhere

    # Owned elsewhere counts as posse for every later transition, and for hiding Quero.
    assert {:ok, _} = Library.set_status(user, game, :zerado)

    assert Library.status_options(Shelf.item(user, game)) == [
             :backlog,
             :jogando,
             :pausado,
             :larguei
           ]
  end

  test "Backlog has no Joguei em outro lugar escape", %{user: user, game: game} do
    assert_raise FunctionClauseError, fn ->
      Library.set_status(user, game, :backlog, owned_elsewhere: true)
    end
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
             :pausado,
             :zerado,
             :larguei
           ]

    {:ok, _} =
      Library.set_status(user, game, :backlog,
        ownership: %{release_id: ctx.release.id, ownership_type: :digital}
      )

    {:ok, _} = Library.set_status(user, game, :jogando)

    assert Library.status_options(Shelf.item(user, game)) == [
             :backlog,
             :pausado,
             :zerado,
             :larguei
           ]
  end

  test "the first release is the one out first, undated last", %{game: game} = ctx do
    undated = release_fixture(game, %{platform: :switch_2, release_date: nil})

    later =
      release_fixture(game, %{
        platform: :switch_2,
        edition: "Deluxe",
        release_date: ~D[2025-06-05]
      })

    item = Shelf.item(nil, game)
    assert Shelf.first_release(item).id == ctx.release.id
    assert Shelf.first_release(%{item | releases: [undated, later]}).id == later.id
    assert Shelf.first_release(%{item | releases: []}) == nil
  end

  test "the media to buy in is physical only when the entry prefers it", %{user: user, game: game} do
    assert Library.media(nil) == :digital

    for {preference, media} <- [
          physical: :physical,
          physical_preferred: :physical,
          digital: :digital,
          digital_preferred: :digital,
          either: :digital
        ] do
      assert Library.media(%Dockd.Library.Entry{media_preference: preference}) == media
    end

    {:ok, _} = Library.set_status(user, game, :quero)
    assert {:ok, entry} = Library.set_media(user, game.id, :physical)
    assert Library.media(entry) == :physical
    assert Library.set_media(user, Ecto.UUID.generate(), :digital) == {:error, :not_found}
  end

  test "the edition to buy is only ever one of the game's own releases",
       %{user: user, game: game} = ctx do
    edition = release_fixture(game, %{platform: :switch, edition: "Archaeologist Edition"})
    other_game = game_fixture(%{title: "Another game"})
    other_release = release_fixture(other_game, %{platform: :switch})

    {:ok, _} = Library.set_status(user, game, :quero)

    assert {:ok, entry} = Library.set_edition(user, game.id, edition.id)
    assert entry.preferred_release_id == edition.id

    assert {:ok, entry} = Library.set_edition(user, game.id, ctx.release.id)
    assert entry.preferred_release_id == ctx.release.id

    assert Library.set_edition(user, game.id, other_release.id) == {:error, :not_found}
    assert Library.set_edition(user, Ecto.UUID.generate(), edition.id) == {:error, :not_found}
  end

  test "Agora plans a wanted game without a status change or an event",
       %{user: user, game: game} = ctx do
    {:ok, _} = Library.set_status(user, game, :quero)
    events = Activity.list_events(user)

    assert {:ok, %{purchase_intent: :planned}} = Library.plan(user, game.id, true)
    assert Shelf.item(user, game).status == :quero
    assert {:ok, %{purchase_intent: :want}} = Library.plan(user, game.id, false)
    assert Activity.list_events(user) == events

    {:ok, _} = Library.plan(user, game.id, true)

    # Switching media keeps Agora: it is no longer digital-only.
    assert {:ok, %{purchase_intent: :planned, media_preference: :physical}} =
             Library.set_media(user, game.id, :physical)

    assert Activity.list_events(user) == events

    {:ok, _} =
      Library.set_status(user, game, :jogando,
        ownership: %{release_id: ctx.release.id, ownership_type: :digital}
      )

    assert Library.plan(user, game.id, true) == {:error, :not_found}
  end

  test "Pausado shares Jogando's tab and count", %{user: user, game: game} = ctx do
    {:ok, _} =
      Library.set_status(user, game, :pausado,
        ownership: %{release_id: ctx.release.id, ownership_type: :digital}
      )

    items = Shelf.list(user)
    assert [%{status: :pausado}] = Shelf.filter(items, %{"tab" => "jogando"})
    assert Shelf.filter(items, %{"tab" => "pausado"}) == []
    assert Shelf.counts(items)["jogando"] == 1
  end

  test "backfill_owned_elsewhere flags played entries left over without posse",
       %{user: user, game: game} = ctx do
    {:ok, _} =
      Library.set_status(user, game, :backlog,
        ownership: %{release_id: ctx.release.id, ownership_type: :digital}
      )

    {:ok, _} = Library.set_status(user, game, :jogando)

    # Undo the posse this rule now requires, as an entry from before it existed would be.
    Dockd.Repo.update_all(Dockd.Library.Entry, set: [owned_elsewhere: false])
    Dockd.Repo.delete_all(Dockd.Library.Ownership)

    untouched = game_fixture(%{title: "Untouched"})
    {:ok, _} = Library.set_status(user, untouched, :quero)

    assert Library.backfill_owned_elsewhere() == 1
    assert Library.get_entry_for_game(user, game.id).owned_elsewhere
    refute Library.get_entry_for_game(user, untouched.id).owned_elsewhere
  end
end
