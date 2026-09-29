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
      {:ok, _} = Library.set_status(bia, game, :jogando)

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
      {:ok, _} = Library.set_status(ana, game, :jogando)
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
      {:ok, _} = Library.set_status(ana, games.playing.game, :jogando)
      {:ok, _} = Library.set_status(ana, games.finished.game, :zerado)
      {:ok, _} = Library.set_status(ana, games.dropped.game, :larguei)
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

    test "Recente says the change behind each current status and nothing bought or owned",
         %{ana: ana, games: games} do
      recent = Social.recent(ana, 10)
      verbs = Map.new(recent, &{&1.item.game.id, &1.verb})

      assert verbs[games.playing.game.id] == "Começou a jogar"
      assert verbs[games.finished.game.id] == "Zerou"
      assert verbs[games.dropped.game.id] == "Largou"
      assert verbs[games.wanted.game.id] == "Quer"
      refute Map.has_key?(verbs, games.owned.game.id)
      refute Map.has_key?(verbs, games.removed.game.id)
      assert length(recent) == 4
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
      {:ok, _} = Library.set_status(bia, games.wanted.game, :jogando)
      {:ok, _} = Library.set_status(caio, games.owned.game, :jogando)

      :ok = Social.follow(ana, bia)
      :ok = Social.follow(bia, ana)
      :ok = Social.follow(ana, caio)

      assert [%{game: game, names: [name]}] = Social.friends_playing(ana)
      assert game.id == games.wanted.game.id
      assert name == bia.name
    end
  end
end
