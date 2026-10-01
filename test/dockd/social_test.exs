defmodule Dockd.SocialTest do
  use Dockd.DataCase, async: true

  import Dockd.DomainFixtures, only: [game_fixture: 1, release_fixture: 2, purchase_fixture: 2]

  alias Dockd.{AccountsFixtures, Library, Social}

  defp account(email), do: AccountsFixtures.user_fixture(%{email: email})

  describe "username" do
    test "comes from the email, without accents, symbols or case" do
      assert account("Joao.Silva@example.com").username == "joaosilva"
      assert account("mário_2@example.com").username == "mario2"
    end

    test "takes the next number when the name is taken" do
      assert account("ana@example.com").username == "ana"
      assert account("ana@example.org").username == "ana2"
      assert account("ana@example.net").username == "ana3"
    end
  end

  describe "following" do
    setup do
      %{ana: account("ana@example.com"), bia: account("bia@example.com")}
    end

    test "goes one way until both follow, and then they are friends", %{ana: ana, bia: bia} do
      assert Social.relation(ana, bia) == :none
      assert Social.relation(nil, bia) == :visitor
      assert Social.relation(ana, ana) == :self

      assert :ok = Social.follow(ana, bia)
      assert :ok = Social.follow(ana, bia)
      assert Social.relation(ana, bia) == :following
      assert Social.relation(bia, ana) == :followed_by
      assert Social.counts(bia) == %{following: 0, followers: 1}

      assert :ok = Social.follow(bia, ana)
      assert Social.relation(ana, bia) == :friends
      assert Social.relation(bia, ana) == :friends

      assert :ok = Social.unfollow(ana, bia)
      assert Social.relation(ana, bia) == :followed_by
    end

    test "never follows itself", %{ana: ana} do
      assert {:error, :self} = Social.follow(ana, ana)
    end

    test "lists followers and followed with their game and relation to the viewer",
         %{ana: ana, bia: bia} do
      caio = account("caio@example.com")
      game = game_fixture(%{title: "Elden Ring"})
      {:ok, _} = Library.set_status(bia, game, :jogando, owned_elsewhere: true)

      :ok = Social.follow(bia, ana)
      :ok = Social.follow(caio, ana)
      :ok = Social.follow(ana, bia)

      [first, second] = Social.people(ana, :followers, ana)
      assert first.user.id == caio.id
      assert first.relation == :followed_by
      assert second.user.id == bia.id
      assert second.relation == :friends
      assert second.playing.title == "Elden Ring"

      assert [%{user: %{id: id}, relation: :visitor}] = Social.people(ana, :following, nil)
      assert id == bia.id
    end
  end

  describe "visibility" do
    test "is public by default; Só amigos opens only to friends and the owner" do
      ana = account("ana@example.com")
      assert ana.profile_visibility == :public
      assert Social.visible?(ana, :visitor)

      {:ok, ana} = Social.set_visibility(ana, "friends")
      refute Social.visible?(ana, :visitor)
      refute Social.visible?(ana, :none)
      refute Social.visible?(ana, :following)
      assert Social.visible?(ana, :friends)
      assert Social.visible?(ana, :self)
    end
  end

  describe "search_users" do
    test "matches the username or the name, minding neither case nor position" do
      ana = account("Ana.Maria@example.com")

      assert [%{user: found}] = Social.search_users("ana", nil)
      assert found.id == ana.id
      assert [%{user: found}] = Social.search_users("MARIA", nil)
      assert found.id == ana.id
      assert [%{user: found}] = Social.search_users("naMar", nil)
      assert found.id == ana.id
      assert Social.search_users("", nil) == []
      assert Social.search_users("ninguem", nil) == []
    end

    test "carries what the account plays now, how many it finished and its relation" do
      ana = account("ana@example.com")
      bia = account("bia@example.com")
      game = game_fixture(%{title: "Elden Ring"})
      {:ok, _} = Library.set_status(ana, game, :jogando, owned_elsewhere: true)
      :ok = Social.follow(bia, ana)
      :ok = Social.follow(ana, bia)

      assert [%{user: found, playing: playing, relation: :friends}] =
               Social.search_users("ana", bia)

      assert found.id == ana.id
      assert playing.id == game.id
    end

    test "hides a Só amigos profile from anyone who is not a friend nor the owner" do
      ana = account("ana@example.com")
      bia = account("bia@example.com")
      {:ok, ana} = Social.set_visibility(ana, "friends")

      assert Social.search_users("ana", nil) == []
      assert Social.search_users("ana", bia) == []
      assert [%{user: found}] = Social.search_users("ana", ana)
      assert found.id == ana.id

      :ok = Social.follow(bia, ana)
      :ok = Social.follow(ana, bia)
      assert [%{user: found}] = Social.search_users("ana", bia)
      assert found.id == ana.id
    end
  end

  describe "the profile" do
    setup do
      ana = account("ana@example.com")

      games =
        Map.new(~w(playing finished wanted owned dropped removed)a, fn key ->
          game = game_fixture(%{title: "Game #{key}"})
          {key, %{game: game, release: release_fixture(game, %{})}}
        end)

      {:ok, _} = Library.set_status(ana, games.wanted.game, :quero)

      {:ok, _} =
        Library.set_status(ana, games.playing.game, :jogando,
          ownership: %{release_id: games.playing.release.id, ownership_type: :digital}
        )

      {:ok, _} =
        Library.set_status(ana, games.finished.game, :zerado,
          ownership: %{release_id: games.finished.release.id, ownership_type: :physical}
        )

      {:ok, _} =
        Library.set_status(ana, games.dropped.game, :larguei,
          ownership: %{release_id: games.dropped.release.id, ownership_type: :digital}
        )

      {:ok, _} = Library.set_status(ana, games.removed.game, :quero)
      {:ok, _} = Library.set_status(ana, games.removed.game, nil)

      {:ok, _} =
        Library.set_status(ana, games.owned.game, :backlog,
          ownership: %{release_id: games.owned.release.id, ownership_type: :digital}
        )

      {:ok, _} = purchase_fixture(ana, games.finished.release)
      %{ana: ana, games: games}
    end

    test "shelves Jogando, Zerados and Quero, never Backlog nor Larguei", %{ana: ana} = ctx do
      shelf = Social.shelf(ana)
      assert Enum.map(shelf.jogando, & &1.game.id) == [ctx.games.playing.game.id]
      assert Enum.map(shelf.zerado, & &1.game.id) == [ctx.games.finished.game.id]
      assert Enum.map(shelf.quero, & &1.game.id) == [ctx.games.wanted.game.id]
      refute Map.has_key?(shelf, :backlog)
    end

    test "puts a catalog game in a position, never more than four", %{ana: ana, games: games} do
      outside = game_fixture(%{title: "Outer Wilds"})
      g = games

      for {game, position} <- [
            {g.playing.game, 1},
            {g.finished.game, 2},
            {g.wanted.game, 3},
            {outside, 4}
          ],
          do: assert(:ok = Social.put_favorite(ana, game, position))

      assert Enum.map(Social.favorite_slots(ana), & &1.game_id) ==
               Enum.map([g.playing.game, g.finished.game, g.wanted.game, outside], & &1.id)

      assert_raise FunctionClauseError, fn -> Social.put_favorite(ana, g.owned.game, 5) end
      assert length(Social.favorites(ana)) == 4
    end

    test "replaces the game in a position and moves one that was elsewhere", %{
      ana: ana,
      games: games
    } do
      :ok = Social.put_favorite(ana, games.playing.game, 1)
      :ok = Social.put_favorite(ana, games.finished.game, 2)

      # a new game takes position 2 and the one there leaves
      :ok = Social.put_favorite(ana, games.wanted.game, 2)
      assert ids(ana) == [games.playing.game.id, games.wanted.game.id]

      # a game that was elsewhere moves and swaps with the occupant
      :ok = Social.put_favorite(ana, games.playing.game, 2)
      assert ids(ana) == [games.wanted.game.id, games.playing.game.id]

      # moving into an empty position leaves its old one empty
      :ok = Social.put_favorite(ana, games.playing.game, 4)
      assert [wanted, nil, nil, playing] = Social.favorite_slots(ana)
      assert {wanted.game_id, playing.game_id} == {games.wanted.game.id, games.playing.game.id}
    end

    test "empties a position and keeps the others where they are", %{ana: ana, games: games} do
      :ok = Social.put_favorite(ana, games.playing.game, 1)
      :ok = Social.put_favorite(ana, games.finished.game, 2)

      :ok = Social.clear_favorite(ana, 1)
      assert [nil, favorite, nil, nil] = Social.favorite_slots(ana)
      assert favorite.game_id == games.finished.game.id
    end

    test "a favorite stays when the game leaves the library", %{ana: ana, games: games} do
      :ok = Social.put_favorite(ana, games.playing.game, 1)
      assert {:ok, :ok} = Library.set_status(ana, games.playing.game, nil)
      assert ids(ana) == [games.playing.game.id]
    end

    test "counts the library by the six statuses, without prices or purchases", %{ana: ana} do
      stats = Social.profile_stats(ana)

      assert stats.games == 5

      assert stats.statuses == %{
               quero: 1,
               backlog: 1,
               jogando: 1,
               pausado: 0,
               zerado: 1,
               larguei: 1
             }
    end

    test "the year summary counts the year's records and the games finished by month",
         %{ana: ana, games: games} do
      diary = Social.diary(ana)
      today = Date.utc_today()
      summary = Social.year_summary(diary, today.year)

      assert summary.records == length(diary)
      assert length(summary.finished) == 12
      assert Enum.at(summary.finished, today.month - 1) == 1
      assert Enum.sum(summary.finished) == 1

      assert Social.year_summary(diary, today.year - 1) == %{
               records: 0,
               finished: List.duplicate(0, 12)
             }

      assert games.finished.game
    end

    test "the Diário groups by month, newest first, up to the limit", %{ana: ana} do
      diary = Social.diary(ana)
      today = Date.utc_today()

      assert [{month, entries}] = Social.diary_months(diary, 3)
      assert month == Date.beginning_of_month(today)
      assert length(entries) == 3

      older = %{hd(diary) | at: ~U[2025-12-31 12:00:00Z]}

      assert [{^month, _}, {~D[2025-12-01], [^older]}] =
               Social.diary_months([hd(diary), older], 5)
    end

    test "the Diário lists every status change of games still in the library",
         %{ana: ana, games: games} do
      {:ok, _} = Library.set_status(ana, games.playing.game, :zerado)
      diary = Social.diary(ana)
      marks = Enum.map(diary, &{&1.item.game.id, &1.status})

      assert hd(marks) == {games.playing.game.id, :zerado}
      assert {games.playing.game.id, :jogando} in marks
      assert {games.owned.game.id, :backlog} in marks
      assert {games.wanted.game.id, :quero} in marks
      assert {games.dropped.game.id, :larguei} in marks
      refute Enum.any?(marks, fn {id, _} -> id == games.removed.game.id end)
      assert length(diary) == 6
    end

    test "Amigos jogando shows only what mutual follows play", %{ana: ana, games: games} do
      bia = account("bia@example.com")
      caio = account("caio@example.com")

      {:ok, _} =
        Library.set_status(bia, games.wanted.game, :jogando,
          ownership: %{release_id: games.wanted.release.id, ownership_type: :digital}
        )

      {:ok, _} =
        Library.set_status(caio, games.owned.game, :jogando,
          ownership: %{release_id: games.owned.release.id, ownership_type: :digital}
        )

      :ok = Social.follow(ana, bia)
      :ok = Social.follow(bia, ana)
      :ok = Social.follow(ana, caio)

      assert [%{game: game, names: [name]}] = Social.friends_playing(ana)
      assert game.id == games.wanted.game.id
      assert name == bia.name
    end
  end

  defp ids(user), do: Enum.map(Social.favorites(user), & &1.game_id)
end
