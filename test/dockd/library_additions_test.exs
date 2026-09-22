defmodule Dockd.LibraryAdditionsTest do
  use Dockd.DataCase, async: false
  import Dockd.DomainFixtures
  alias Dockd.Library

  setup do
    {:ok, user} = user_fixture()
    game = game_fixture(%{title: "Metroid Prime 4"})
    %{user: user, game: game}
  end

  test "filters entries by title and state", %{user: user, game: game} do
    assert {:ok, _} = entry_fixture(user, game, %{backlog: :backlog, play_state: :playing})

    assert [%{game: %{title: "Metroid Prime 4"}}] =
             Library.list_entries(user, %{"search" => "metroid", "backlog" => "backlog"})

    assert [] = Library.list_entries(user, %{"search" => "zelda"})
  end

  test "collection tab only returns entries with an owned release", %{user: user} do
    owned_game = game_fixture(%{title: "Owned game"})
    wish = game_fixture(%{title: "Wish game"})
    release = release_fixture(owned_game)

    {:ok, _ownership} =
      Library.create_ownership(user, %{
        release_id: release.id,
        ownership_type: :digital,
        acquired_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, _} = entry_fixture(user, owned_game)
    {:ok, _} = entry_fixture(user, wish, %{purchase_intent: :want})

    assert [%{game: %{title: "Owned game"}}] = Library.list_entries(user, %{"tab" => "all"})
  end

  test "finds an entry by game within the user scope", %{user: user, game: game} do
    assert {:ok, entry} = entry_fixture(user, game)
    assert Library.get_entry_by_game(user, game.id).id == entry.id
  end
end
