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

  test "finds an entry by game within the user scope", %{user: user, game: game} do
    assert {:ok, entry} = entry_fixture(user, game)
    assert Library.get_entry_by_game(user, game.id).id == entry.id
  end
end
