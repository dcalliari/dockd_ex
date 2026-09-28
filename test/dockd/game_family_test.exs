defmodule Dockd.GameFamilyTest do
  use Dockd.DataCase, async: false
  import Dockd.DomainFixtures
  alias Dockd.Activity.Event
  alias Dockd.{Catalog, IGDB, Library, Purchasing}
  alias Dockd.Catalog.{Game, GameLink, IgdbFamily, Release}
  alias Dockd.Library.{Entry, Ownership, ReleaseVeto}
  alias Dockd.Pricing.{StoreListing, StorePrice}
  alias Dockd.Purchasing.{PriceObservation, Purchase}

  # IGDB entries as the API gave them on 2026-09-28, trimmed to what the family uses.
  @totk %{
    "id" => 119_388,
    "name" => "The Legend of Zelda: Tears of the Kingdom",
    "platforms" => [%{"id" => 130}],
    "release_dates" => [%{"platform" => 130, "date" => 1_683_849_600}]
  }
  @totk_switch_2 %{
    "id" => 338_073,
    "name" => "The Legend of Zelda: Tears of the Kingdom - Nintendo Switch 2 Edition",
    "parent_game" => 119_388,
    "game_type" => 10,
    "platforms" => [%{"id" => 508}],
    "release_dates" => [%{"platform" => 508, "date" => 1_749_081_600}]
  }
  @totk_collector %{
    "id" => 237_289,
    "name" => "The Legend of Zelda: Tears of the Kingdom - Collector's Edition",
    "version_parent" => 119_388,
    "version_title" => "Collector's Edition",
    "game_type" => 0,
    "platforms" => [%{"id" => 130}]
  }
  @totk_mod %{
    "id" => 252_906,
    "name" => "The Legend of Zelda: Tears of the Kingdom - Better Sages Mod",
    "parent_game" => 119_388,
    "game_type" => 5,
    "platforms" => [%{"id" => 130}]
  }
  @botw %{
    "id" => 7346,
    "name" => "The Legend of Zelda: Breath of the Wild",
    "platforms" => [%{"id" => 41}, %{"id" => 130}],
    "release_dates" => [%{"platform" => 130, "date" => 1_488_499_200}]
  }
  @botw_switch_2 %{
    "id" => 338_072,
    "name" => "The Legend of Zelda: Breath of the Wild - Nintendo Switch 2 Edition",
    "parent_game" => 7346,
    "game_type" => 10,
    "platforms" => [%{"id" => 508}],
    "release_dates" => [%{"platform" => 508, "date" => 1_749_081_600}]
  }
  @thps %{
    "id" => 334_243,
    "name" => "Tony Hawk's Pro Skater 3+4",
    "platforms" => [%{"id" => 6}, %{"id" => 130}, %{"id" => 508}],
    "release_dates" => [
      %{"platform" => 130, "date" => 1_752_192_000},
      %{"platform" => 508, "date" => 1_752_192_000}
    ]
  }
  @thps_deluxe %{
    "id" => 334_422,
    "name" => "Tony Hawk's Pro Skater 3 + 4: Digital Deluxe Edition",
    "version_parent" => 334_243,
    "version_title" => "Digital Deluxe Edition",
    "game_type" => 3,
    "platforms" => [%{"id" => 6}, %{"id" => 130}],
    "release_dates" => [%{"platform" => 130, "date" => 1_752_192_000}]
  }
  @aoc %{
    "id" => 136_848,
    "name" => "Hyrule Warriors: Age of Calamity",
    "platforms" => [%{"id" => 130}],
    "release_dates" => [%{"platform" => 130, "date" => 1_605_830_400}]
  }
  @aoc_definitive %{
    "id" => 400_001,
    "name" => "Hyrule Warriors: Age of Calamity - Definitive Edition",
    "parent_game" => 136_848,
    "game_type" => 10,
    "platforms" => [%{"id" => 508}],
    "release_dates" => [%{"platform" => 508, "date" => 1_790_000_000}]
  }
  @aoc_remake %{
    "id" => 400_002,
    "name" => "Hyrule Warriors: Age of Calamity Reborn",
    "parent_game" => 136_848,
    "game_type" => 8,
    "platforms" => [%{"id" => 508}]
  }
  @pc_only %{"id" => 500_001, "name" => "Old PC Game", "platforms" => [%{"id" => 6}]}
  @pc_only_edition %{
    "id" => 500_002,
    "name" => "Old PC Game: Complete Edition",
    "version_parent" => 500_001,
    "platforms" => [%{"id" => 130}],
    "release_dates" => [%{"platform" => 130, "date" => 1_700_000_000}]
  }

  @entries [
    @totk,
    @totk_switch_2,
    @totk_collector,
    @totk_mod,
    @botw,
    @botw_switch_2,
    @thps,
    @thps_deluxe,
    @aoc,
    @aoc_definitive,
    @aoc_remake,
    @pc_only,
    @pc_only_edition
  ]

  setup do
    Application.put_env(:dockd, :igdb,
      client_id: "test-id",
      client_secret: "test-secret",
      req_options: [plug: {Req.Test, "igdb-family"}]
    )

    IGDB.clear_cache()
    stub_igdb(@entries)
    on_exit(fn -> Application.put_env(:dockd, :igdb, []) end)
    {:ok, user} = user_fixture()
    %{user: user}
  end

  # Answers IGDB like the API would, from `entries`: by id, by parent, or a search
  # returning every entry sold on a Nintendo platform.
  defp stub_igdb(entries) do
    test = self()

    Req.Test.stub("igdb-family", fn conn ->
      case conn.request_path do
        "/oauth2/token" ->
          Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

        "/v4/games" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:igdb, body})
          Req.Test.json(conn, answer(body, entries))
      end
    end)
  end

  defp answer(body, entries) do
    ids = fn pattern ->
      case Regex.run(pattern, body) do
        [_, ids] -> ids |> String.split(",") |> Enum.map(&String.to_integer/1)
        nil -> nil
      end
    end

    cond do
      parents = ids.(~r/version_parent = \(([\d,]+)\)/) ->
        Enum.filter(entries, fn entry ->
          (entry["version_parent"] in parents or entry["parent_game"] in parents) and
            IgdbFamily.nintendo?(entry)
        end)

      wanted = ids.(~r/where id = \(([\d,]+)\)/) ->
        Enum.filter(entries, &(&1["id"] in wanted))

      true ->
        Enum.filter(entries, &IgdbFamily.nintendo?/1)
    end
  end

  defp releases(game),
    do:
      game.id
      |> Catalog.list_releases()
      |> Enum.map(&{&1.platform, &1.edition, &1.release_date})
      |> Enum.sort()

  defp link(igdb_id), do: Repo.get_by(GameLink, igdb_id: igdb_id)

  describe "IgdbFamily.relation/1" do
    test "an edition and the Switch 2 Edition join; remasters, expansions and ports ask" do
      assert IgdbFamily.relation(@totk_collector) == {:version, 119_388}
      assert IgdbFamily.relation(@thps_deluxe) == {:version, 334_243}
      assert IgdbFamily.relation(@totk_switch_2) == {:switch_2_edition, 119_388}
      assert IgdbFamily.relation(@aoc_definitive) == {:expanded, 136_848}
      assert IgdbFamily.relation(%{@aoc_definitive | "game_type" => 9}) == {:remaster, 136_848}

      assert IgdbFamily.relation(%{
               "parent_game" => 109_462,
               "game_type" => 11,
               "name" => "Animal Crossing: New Horizons - Nintendo Switch 2 Edition",
               "platforms" => [%{"id" => 508}]
             }) == {:switch_2_edition, 109_462}

      assert IgdbFamily.relation(@aoc_remake) == :own
      assert IgdbFamily.relation(@totk_mod) == :own
      assert IgdbFamily.relation(@totk) == :own
      assert IgdbFamily.automatic?(:version) and IgdbFamily.automatic?(:switch_2_edition)
      refute IgdbFamily.automatic?(:expanded)
    end

    test "a Switch 2 Edition must be sold only on Switch 2 and say so" do
      both = %{@totk_switch_2 | "platforms" => [%{"id" => 130}, %{"id" => 508}]}
      assert IgdbFamily.relation(both) == {:expanded, 119_388}

      assert IgdbFamily.relation(%{@totk_switch_2 | "name" => "Tears of the Kingdom Plus"}) ==
               {:expanded, 119_388}
    end
  end

  describe "import_igdb/1" do
    test "an edition imports its parent game, with the Switch 2 Edition as a release" do
      assert {:ok, %Game{igdb_id: 119_388} = game} = Catalog.import_igdb(237_289)
      assert game.title == "The Legend of Zelda: Tears of the Kingdom"

      assert releases(game) == [
               {:switch, "Edição padrão", ~D[2023-05-12]},
               {:switch_2, "Edição padrão", ~D[2025-06-05]}
             ]

      assert %{game_id: id, kind: :version, match: :auto} = link(237_289)
      assert id == game.id
      assert %{kind: :switch_2_edition, match: :auto} = link(338_073)
      refute link(252_906)

      # Every entry of the game finds it, without asking IGDB again.
      flush_igdb()
      assert {:ok, %{id: ^id}} = Catalog.import_igdb(338_073)
      assert {:ok, %{id: ^id}} = Catalog.import_igdb(119_388)
      refute_received {:igdb, _}
      assert Repo.aggregate(Game, :count) == 1
    end

    test "the Switch 2 Edition imports its parent with both releases" do
      assert {:ok, game} = Catalog.import_igdb(338_073)
      assert game.igdb_id == 119_388
      assert Enum.map(game.releases, & &1.platform) |> Enum.sort() == [:switch, :switch_2]
    end

    test "an edition of a game not sold on Nintendo is the game" do
      assert {:ok, game} = Catalog.import_igdb(500_002)
      assert game.igdb_id == 500_002
      assert releases(game) == [{:switch, "Edição padrão", ~D[2023-11-14]}]
      refute link(500_002)
    end

    test "a remaster, expansion or port of a game here comes in apart and waits for review" do
      {:ok, aoc} = Catalog.import_igdb(136_848)
      {:ok, definitive} = Catalog.import_igdb(400_001)

      assert definitive.id != aoc.id
      assert %{game_id: game_id, kind: :expanded, match: :review} = link(400_001)
      assert game_id == aoc.id
      assert [%{game: %{id: ^game_id}, candidate: %{id: candidate}}] = Catalog.list_review_links()
      assert candidate == definitive.id
      assert Catalog.review_link_count() == 1
    end

    test "the parent imported after its doubtful child asks too" do
      {:ok, definitive} = Catalog.import_igdb(400_001)
      {:ok, aoc} = Catalog.import_igdb(136_848)

      assert %{match: :review} = link(400_001)

      assert [%{game: %{id: game_id}, candidate: %{id: candidate_id}}] =
               Catalog.list_review_links()

      assert {game_id, candidate_id} == {aoc.id, definitive.id}
    end

    test "a remake is always another game" do
      {:ok, aoc} = Catalog.import_igdb(136_848)
      {:ok, remake} = Catalog.import_igdb(400_002)

      assert remake.id != aoc.id
      assert Catalog.list_review_links() == []
    end
  end

  describe "review links" do
    setup do
      {:ok, aoc} = Catalog.import_igdb(136_848)
      {:ok, definitive} = Catalog.import_igdb(400_001)
      %{aoc: aoc, definitive: definitive, link: link(400_001)}
    end

    test "the same game: the candidate merges into the game", ctx do
      {:ok, _} = Library.set_status(ctx.user, ctx.definitive, :quero)

      assert {:ok, game, _undo} = Catalog.confirm_game_link(ctx.link)
      assert game.id == ctx.aoc.id
      assert Enum.map(game.releases, & &1.platform) |> Enum.sort() == [:switch, :switch_2]
      refute Repo.get(Game, ctx.definitive.id)
      assert %{match: :confirmed, kind: :expanded, game_id: id} = link(400_001)
      assert id == ctx.aoc.id
      assert Repo.get_by!(Entry, user_id: ctx.user.id).game_id == ctx.aoc.id
      assert Catalog.list_review_links() == []
      assert Catalog.get_game_by_igdb_id(400_001).id == ctx.aoc.id
    end

    test "Desfazer puts the two games back and asks again", ctx do
      {:ok, _} = Library.set_status(ctx.user, ctx.definitive, :quero)
      before = snapshot()

      assert {:ok, _game, undo} = Catalog.confirm_game_link(ctx.link)
      refute Repo.get(Game, ctx.definitive.id)

      assert :ok = Catalog.undo_merge(undo)
      assert snapshot() == before
      assert [%{candidate: %{id: candidate}}] = Catalog.list_review_links()
      assert candidate == ctx.definitive.id
    end

    test "Desfazer after another game asks again", ctx do
      {:ok, rejected} = Catalog.reject_game_link(ctx.link)
      assert {:ok, %{match: :review}} = Catalog.reopen_game_link(rejected)
      assert Catalog.review_link_count() == 1
      assert {:error, :not_rejected} = Catalog.reopen_game_link(link(400_001))
    end

    test "another game: rejected for good", ctx do
      assert {:ok, %{match: :rejected}} = Catalog.reject_game_link(ctx.link)
      assert {:error, :not_in_review} = Catalog.confirm_game_link(link(400_001))
      assert Repo.get(Game, ctx.definitive.id)

      Catalog.resolve_families()
      assert %{match: :rejected} = link(400_001)
      assert Catalog.list_review_links() == []
    end
  end

  describe "sync_igdb/0 and the platforms of a game" do
    # The Switch 2 remake as IGDB gave it on 2026-09-28: no Switch release.
    @ocarina %{
      "id" => 405_460,
      "name" => "The Legend of Zelda: Ocarina of Time",
      "platforms" => [%{"id" => 508}],
      "parent_game" => 1029,
      "release_dates" => [%{"platform" => 508, "date" => 1_793_836_800, "date_format" => 0}]
    }

    setup do
      stub_igdb([@ocarina | @entries])

      game =
        game_fixture(%{
          title: "The Legend of Zelda: Ocarina of Time",
          availability: :nintendo_exclusive,
          igdb_id: 405_460
        })

      switch =
        release_fixture(game, %{platform: :switch, physical_available: true})

      %{game: game, switch: switch}
    end

    test "a release on a platform IGDB does not list for the game goes away", ctx do
      assert {:ok, _} = Catalog.sync_igdb()
      assert releases(ctx.game) == [{:switch_2, "Edição padrão", ~D[2026-11-05]}]
    end

    test "an unlisted release someone bought, or the eShop sells, stays", ctx do
      {:ok, _} = purchase_fixture(ctx.user, ctx.switch)
      assert {:ok, _} = Catalog.sync_igdb()
      assert Enum.any?(releases(ctx.game), &match?({:switch, _, _}, &1))

      other = game_fixture(%{title: "Sold", igdb_id: 9_001})
      sold = release_fixture(other, %{platform: :switch_2})
      store_price_fixture(sold)

      solo = %{
        "id" => 9_001,
        "name" => "Sold",
        "platforms" => [%{"id" => 130}],
        "release_dates" => [%{"platform" => 130, "date" => 1_683_849_600}]
      }

      stub_igdb([solo, @ocarina | @entries])
      assert {:ok, _} = Catalog.sync_igdb()
      assert Enum.any?(releases(other), &match?({:switch_2, _, _}, &1))
    end

    test "a release an entry joined to the game lists stays", ctx do
      Repo.insert!(%GameLink{
        igdb_id: 119_388,
        game_id: ctx.game.id,
        kind: :merged,
        match: :confirmed
      })

      assert {:ok, _} = Catalog.sync_igdb()
      assert Enum.any?(releases(ctx.game), &match?({:switch, _, _}, &1))
    end
  end

  describe "resolve_families/1" do
    test "gives a game its Switch 2 release from the Switch 2 Edition entry" do
      game = game_fixture(%{title: "Zelda TotK", igdb_id: 119_388})
      release_fixture(game, %{platform: :switch, edition: "Edição padrão"})

      assert [
               %{step: :link, igdb_id: 237_289},
               %{step: :link, igdb_id: 338_073},
               %{step: :switch_2_release, igdb_id: 338_073}
             ] =
               Enum.sort_by(Catalog.resolve_families(), &{&1.igdb_id, &1.step})

      assert [{:switch, _, _}, {:switch_2, "Edição padrão", ~D[2025-06-05]}] = releases(game)

      # Idempotent: the release is kept and dated, nothing else changes.
      Catalog.resolve_families()
      assert length(releases(game)) == 2
      assert Repo.aggregate(GameLink, :count) == 2
    end

    test "a game imported by its edition's entry moves to the parent's", %{user: user} do
      game = game_fixture(%{title: "Tony Hawk's Pro Skater 3 + 4", igdb_id: 334_422})
      release = release_fixture(game, %{platform: :switch})

      {:ok, _} =
        Library.set_status(user, game, :backlog,
          ownership: %{release_id: release.id, ownership_type: :digital}
        )

      assert [%{step: :repoint, igdb_id: 334_243, from: 334_422}] = Catalog.resolve_families()

      game = Repo.get!(Game, game.id)
      assert game.igdb_id == 334_243
      assert %{kind: :version, match: :auto} = link(334_422)
      assert [%{release_id: release_id}] = Repo.all(Ownership)
      assert release_id == release.id
      assert Catalog.get_game_by_igdb_id(334_422).id == game.id
    end

    test "dry run changes nothing" do
      game = game_fixture(%{title: "Tony Hawk's Pro Skater 3 + 4", igdb_id: 334_422})
      botw = game_fixture(%{title: "BotW", igdb_id: 7346})
      release_fixture(botw, %{platform: :switch})

      steps = Catalog.resolve_families(dry_run: true)
      assert Enum.any?(steps, &(&1.step == :repoint and &1.game.id == game.id))
      assert Enum.any?(steps, &(&1.step == :switch_2_release and &1.game.id == botw.id))
      assert Repo.get!(Game, game.id).igdb_id == 334_422
      assert length(releases(botw)) == 1
      assert Repo.aggregate(GameLink, :count) == 0
    end

    test "merges a Switch 2 Edition imported as a game of its own", %{user: user} do
      totk = game_fixture(%{title: "Zelda TotK", igdb_id: 119_388})
      switch = release_fixture(totk, %{platform: :switch})
      {:ok, _} = Library.set_status(user, totk, :quero)

      duplicate = game_fixture(%{title: "Zelda TotK NS2", igdb_id: 338_073})
      switch_2 = release_fixture(duplicate, %{platform: :switch_2})
      {:ok, _purchase} = purchase_fixture(user, switch_2, %{price_cents: 43_990})

      Catalog.resolve_families()

      refute Repo.get(Game, duplicate.id)
      assert [{:switch, _, _}, {:switch_2, "Edição padrão", ~D[2025-06-05]}] = releases(totk)
      assert Repo.get!(Release, switch_2.id).game_id == totk.id
      assert Repo.get!(Release, switch.id).game_id == totk.id
      assert %{kind: :switch_2_edition, match: :auto} = link(338_073)
      assert [%{game_id: game_id}] = Repo.all(Entry)
      assert game_id == totk.id
      assert Library.Shelf.item(user, Catalog.get_game!(totk.id)).status == :backlog
    end
  end

  describe "merge_games/3" do
    # The case measured on the owner's backup: the Switch 2 Edition of TotK imported
    # as its own game, bought on Switch 2, with a physical Switch copy and a veto.
    test "moves everything that belongs to the absorbed game", %{user: user} do
      totk = game_fixture(%{title: "Zelda TotK", igdb_id: 119_388})
      switch = release_fixture(totk, %{platform: :switch, physical_available: true})

      {:ok, _} =
        Library.create_entry(user, %{
          game_id: totk.id,
          purchase_intent: :want,
          priority: :high,
          notes: "presente"
        })

      loser = game_fixture(%{title: "Zelda TotK NS2", igdb_id: 338_073})
      loser_switch = release_fixture(loser, %{platform: :switch, physical_available: true})
      loser_switch_2 = release_fixture(loser, %{platform: :switch_2})

      old = ~U[2025-01-01 00:00:00.000000Z]

      {:ok, _} =
        Library.set_status(user, totk, :backlog,
          ownership: %{release_id: switch.id, ownership_type: :physical}
        )

      physical = Repo.get_by!(Ownership, release_id: switch.id)

      Repo.insert!(%Ownership{
        user_id: user.id,
        release_id: loser_switch.id,
        ownership_type: :physical,
        acquired_at: old
      })

      Repo.insert!(%ReleaseVeto{user_id: user.id, release_id: loser_switch.id})
      Repo.insert!(%ReleaseVeto{user_id: user.id, release_id: switch.id})

      {:ok, purchase} = purchase_fixture(user, loser_switch_2, %{price_cents: 43_990})

      {:ok, _} =
        Purchasing.create_price_observation(user, %{
          release_id: loser_switch_2.id,
          format: :digital,
          price_cents: 43_990,
          observed_at: DateTime.utc_now(),
          source: "OLX"
        })

      store_price_fixture(loser_switch_2, %{regular_cents: 43_990})

      {:ok, _} =
        Library.create_entry(user, %{
          game_id: loser.id,
          play_state: :playing,
          priority: :low,
          target_price_cents: 30_000,
          notes: "comprei na promoção"
        })

      events = Repo.aggregate(Event, :count)

      assert {:ok, game} = Catalog.merge_games(Catalog.get_game!(totk.id), loser)
      assert game.id == totk.id

      refute Repo.get(Game, loser.id)
      refute Repo.get(Release, loser_switch.id)
      assert Repo.get!(Release, loser_switch_2.id).game_id == totk.id

      assert [kept] = Repo.all(from o in Ownership, where: o.ownership_type == :physical)
      assert kept.id == physical.id and kept.release_id == switch.id
      assert kept.acquired_at == old

      assert Repo.get_by!(Ownership, ownership_type: :digital).release_id == loser_switch_2.id
      assert Repo.get!(Purchase, purchase.id).release_id == loser_switch_2.id
      assert Repo.aggregate(PriceObservation, :count) == 1
      assert [%{release_id: vetoed}] = Repo.all(ReleaseVeto)
      assert vetoed == switch.id
      assert Repo.get_by(StoreListing, release_id: loser_switch_2.id)
      assert Repo.aggregate(StorePrice, :count) == 1

      assert Repo.aggregate(Event, :count) == events
      assert Repo.all(from e in Event, where: e.game_id == ^loser.id) == []

      assert [entry] = Repo.all(Entry)
      assert entry.game_id == totk.id
      assert entry.play_state == :playing
      assert entry.priority == :high
      assert entry.target_price_cents == 30_000
      assert entry.notes == "presente\ncomprei na promoção"

      assert %{kind: :merged, match: :confirmed, game_id: game_id} = link(338_073)
      assert game_id == totk.id
      assert Library.Shelf.item(user, game).status == :jogando
    end

    test "Desfazer puts back every row the merge touched", %{user: user} do
      totk = game_fixture(%{title: "Zelda TotK", igdb_id: 119_388})
      switch = release_fixture(totk, %{platform: :switch, physical_available: true})
      loser = game_fixture(%{title: "Zelda TotK NS2", igdb_id: 338_073})
      loser_switch = release_fixture(loser, %{platform: :switch, physical_available: true})
      loser_switch_2 = release_fixture(loser, %{platform: :switch_2})

      {:ok, _} =
        Library.set_status(user, totk, :backlog,
          ownership: %{release_id: switch.id, ownership_type: :physical}
        )

      Repo.insert!(%Ownership{
        user_id: user.id,
        release_id: loser_switch.id,
        ownership_type: :physical,
        acquired_at: ~U[2025-01-01 00:00:00.000000Z]
      })

      Repo.insert!(%ReleaseVeto{user_id: user.id, release_id: loser_switch.id})
      Repo.insert!(%ReleaseVeto{user_id: user.id, release_id: switch.id})
      {:ok, _} = purchase_fixture(user, loser_switch_2, %{price_cents: 43_990})
      store_price_fixture(loser_switch_2, %{regular_cents: 43_990})
      store_price_fixture(switch, %{regular_cents: 38_990})
      Repo.insert!(%StoreListing{release_id: loser_switch.id, store: :eshop_br, match: :review})
      {:ok, _} = Library.create_entry(user, %{game_id: loser.id, play_state: :playing})

      link =
        Repo.insert!(%GameLink{igdb_id: 338_073, game_id: totk.id, kind: :port, match: :review})

      before = snapshot()

      assert {:ok, _game, undo} = Catalog.confirm_game_link(link)
      assert snapshot() != before
      assert :ok = Catalog.undo_merge(undo)
      assert snapshot() == before
    end

    test "a store listing in review gives way to an accepted one" do
      winner = game_fixture(%{title: "Winner"})
      loser = game_fixture(%{title: "Loser"})
      kept = release_fixture(winner, %{platform: :switch})
      moved = release_fixture(loser, %{platform: :switch})

      Repo.insert!(%StoreListing{release_id: kept.id, store: :eshop_br, match: :review})
      store_price_fixture(moved)

      assert {:ok, _} = Catalog.merge_games(winner, loser)
      assert [%{match: :auto, release_id: release_id}] = Repo.all(StoreListing)
      assert release_id == kept.id
      assert Repo.aggregate(StorePrice, :count) == 1
    end

    test "a game never merges into itself" do
      game = game_fixture()
      assert {:error, :same_game} = Catalog.merge_games(game, game)
    end
  end

  # Every row a merge can touch, in a stable order.
  defp snapshot do
    for schema <- [
          Game,
          Release,
          GameLink,
          Entry,
          Ownership,
          ReleaseVeto,
          Purchase,
          PriceObservation,
          Event,
          StoreListing,
          StorePrice
        ],
        into: %{} do
      {schema, schema |> Repo.all() |> Enum.map(&Map.drop(&1, [:__meta__])) |> Enum.sort()}
    end
  end

  defp flush_igdb do
    receive do
      {:igdb, _} -> flush_igdb()
    after
      0 -> :ok
    end
  end
end
