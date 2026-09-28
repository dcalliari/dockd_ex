defmodule Dockd.CatalogCurationTest do
  use Dockd.DataCase, async: false
  @moduletag :capture_log
  import Dockd.DomainFixtures
  alias Dockd.{Catalog, EshopStub, IGDB}
  alias Dockd.Catalog.{Curation, Game, GameLink}

  @cover %{"image_id" => "cover"}
  @switch [%{"id" => 130}]
  @switch_2 [%{"id" => 508}]

  @base %{
    "game_type" => 0,
    "cover" => @cover,
    "platforms" => @switch,
    "release_dates" => [%{"platform" => 130, "date" => 1_683_849_600, "date_format" => 0}]
  }

  # Titles and ids as IGDB has them; the counts are what each case needs.
  @totk Map.merge(@base, %{
          "id" => 119_388,
          "name" => "The Legend of Zelda: Tears of the Kingdom",
          "total_rating_count" => 928,
          "alternative_names" => [%{"name" => "Zelda: TotK"}]
        })
  @totk_switch_2 Map.merge(@base, %{
                   "id" => 338_073,
                   "name" =>
                     "The Legend of Zelda: Tears of the Kingdom - Nintendo Switch 2 Edition",
                   "game_type" => 10,
                   "parent_game" => 119_388,
                   "platforms" => @switch_2,
                   "release_dates" => [
                     %{"platform" => 508, "date" => 1_749_168_000, "date_format" => 0}
                   ]
                 })
  @skyward_hd Map.merge(@base, %{
                "id" => 143_614,
                "name" => "The Legend of Zelda: Skyward Sword HD",
                "game_type" => 9,
                "parent_game" => 534,
                "total_rating_count" => 3
              })
  @online Map.merge(@base, %{
            "id" => 357_440,
            "name" => "The Legend of Zelda: Tears of the Kingdom Online",
            "cover" => nil,
            "total_rating_count" => 50
          })
  @kitten Map.merge(@base, %{"id" => 250_001, "name" => "Kitten Island"})
  @cozy Map.merge(@base, %{
          "id" => 250_002,
          "name" => "Cozy Cooking: Tiny Tastes",
          "total_rating_count" => 12
        })
  @hole Map.merge(@base, %{
          "id" => 250_003,
          "name" => "Hole io",
          "involved_companies" => [
            %{"publisher" => true, "company" => %{"name" => "Qubic Games"}}
          ],
          "total_rating_count" => 40
        })
  @zenge Map.merge(@base, %{"id" => 250_004, "name" => "Zenge", "total_rating_count" => 9})
  @cancelled Map.merge(@base, %{
               "id" => 250_005,
               "name" => "Some Cancelled Game",
               "game_status" => 6,
               "hypes" => 40
             })
  @expansion_pass Map.merge(@base, %{
                    "id" => 41_829,
                    "name" => "The Legend of Zelda: Breath of the Wild - Expansion Pass",
                    "game_type" => 3,
                    "total_rating_count" => 20
                  })
  @three_d_world Map.merge(@base, %{
                   "id" => 138_227,
                   "name" => "Super Mario 3D World + Bowser's Fury",
                   "game_type" => 3,
                   "total_rating_count" => 124
                 })
  @cuphead_bundle Map.merge(@base, %{
                    "id" => 250_006,
                    "name" => "Cuphead & The Delicious Last Course",
                    "game_type" => 3,
                    "total_rating_count" => 11
                  })
  @randomizer Map.merge(@base, %{
                "id" => 331_139,
                "name" => "The Legend of Zelda: Skyward Sword HD Randomizer",
                "game_type" => 5
              })

  @pool [
    @totk,
    @totk_switch_2,
    @skyward_hd,
    @online,
    @kitten,
    @cozy,
    @hole,
    @zenge,
    @cancelled,
    @expansion_pass,
    @three_d_world,
    @cuphead_bundle,
    @randomizer
  ]

  # What IGDB lists inside the collections, and the original Skyward Sword.
  @others [
    %{"id" => 534, "name" => "The Legend of Zelda: Skyward Sword", "total_rating_count" => 900},
    %{"id" => 41_825, "name" => "The Master Trials", "game_type" => 1, "bundles" => [41_829]},
    %{"id" => 41_826, "name" => "The Champions' Ballad", "game_type" => 1, "bundles" => [41_829]},
    %{
      "id" => 1,
      "name" => "Super Mario 3D World",
      "game_type" => 0,
      "bundles" => [138_227],
      "platforms" => [%{"id" => 41}]
    },
    %{
      "id" => 142_909,
      "name" => "Bowser's Fury",
      "game_type" => 0,
      "bundles" => [138_227],
      "platforms" => @switch
    },
    %{
      "id" => 9,
      "name" => "Cuphead",
      "game_type" => 0,
      "bundles" => [250_006],
      "platforms" => @switch
    },
    %{"id" => 10, "name" => "The Delicious Last Course", "game_type" => 1, "bundles" => [250_006]}
  ]

  setup do
    Application.put_env(:dockd, :igdb,
      client_id: "test-id",
      client_secret: "test-secret",
      req_options: [plug: {Req.Test, "igdb-curation"}]
    )

    criteria = Application.fetch_env!(:dockd, :catalog_criteria)
    Application.put_env(:dockd, :catalog_criteria, Keyword.put(criteria, :max_eshop_rank, 1000))
    Application.put_env(:dockd, :eshop, EshopStub.config())
    EshopStub.stub(self())
    IGDB.clear_cache()
    stub_igdb()

    on_exit(fn ->
      Application.put_env(:dockd, :igdb, [])
      Application.put_env(:dockd, :eshop, [])
      Application.put_env(:dockd, :catalog_criteria, criteria)
    end)

    :ok
  end

  defp stub_igdb do
    Req.Test.stub("igdb-curation", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case conn.request_path do
        "/oauth2/token" -> Req.Test.json(conn, %{access_token: "token", expires_in: 3600})
        "/v4/games/count" -> Req.Test.json(conn, %{"count" => 7})
        "/v4/games" -> Req.Test.json(conn, answer(body))
      end
    end)
  end

  defp ids(body, pattern) do
    case Regex.run(pattern, body) do
      [_, ids] -> ids |> String.split(",") |> Enum.map(&String.to_integer/1)
      nil -> nil
    end
  end

  defp answer(body) do
    offset = ids(body, ~r/offset (\d+)/) || [0]

    cond do
      types = ids(body, ~r/game_type = \(([\d,]+)\)/) ->
        @pool
        |> Enum.filter(&(&1["game_type"] in types))
        |> Enum.drop(hd(offset))

      bundles = ids(body, ~r/bundles = \(([\d,]+)\)/) ->
        Enum.filter(@others, &Enum.any?(&1["bundles"] || [], fn b -> b in bundles end))

      wanted = ids(body, ~r/where id = \(([\d,]+)\)/) ->
        Enum.filter(@pool ++ @others, &(&1["id"] in wanted))

      true ->
        []
    end
  end

  describe "survey/1" do
    test "admits popular games and says why it leaves each other one out" do
      assert {:ok, %{decisions: decisions, eshop: :ok}} = Curation.survey()
      by_name = Map.new(decisions, fn {entry, decision} -> {entry["name"], decision} end)

      assert by_name[@totk["name"]] == :admit
      assert by_name[@totk_switch_2["name"]] == :admit
      # Rated little on its own, a lot as the game it remasters.
      assert by_name[@skyward_hd["name"]] == :admit
      # Rated by nobody, but among the most sold at the eShop Brasil.
      assert by_name[@kitten["name"]] == :admit
      assert by_name[@three_d_world["name"]] == :admit

      assert by_name[@online["name"]] == {:exclude, :no_cover}
      # REDDEER.GAMES at the eShop, Qubic Games at IGDB.
      assert by_name[@cozy["name"]] == {:exclude, :publisher}
      assert by_name[@hole["name"]] == {:exclude, :publisher}
      assert by_name[@zenge["name"]] == {:exclude, :unpopular}
      assert by_name[@cancelled["name"]] == {:exclude, :status}
      assert by_name[@expansion_pass["name"]] == {:exclude, :bundle_without_game}
      assert by_name[@cuphead_bundle["name"]] == {:exclude, :edition_of_other}
      # Mods are another game type: IGDB never answers them.
      refute Map.has_key?(by_name, @randomizer["name"])
    end

    test "without the eShop ranking it still decides, and says why" do
      Application.put_env(:dockd, :eshop, [])

      assert {:ok, %{decisions: decisions, eshop: :not_configured}} = Curation.survey()
      assert {@kitten, {:exclude, :unpopular}} in decisions
    end
  end

  describe "curate/1" do
    test "imports what it admits, an edition through its game, and resumes" do
      assert {:ok, report} = Catalog.curate()
      assert report.admitted == 5
      assert report.imported == 4
      assert report.failed == []
      assert report.excluded.publisher == %{count: 2, sample: ["Hole io", @cozy["name"]]}

      totk = Catalog.get_game_by_igdb_id(119_388)
      assert Enum.sort(Enum.map(totk.releases, & &1.platform)) == [:switch, :switch_2]

      assert %{game_id: game_id, kind: :switch_2_edition} =
               Repo.get_by(GameLink, igdb_id: 338_073)

      assert game_id == totk.id
      assert %{rating_count: 928, alternative_names: ["Zelda: TotK"]} = totk

      assert Repo.aggregate(Game, :count) == 4
      assert {:ok, %{imported: 0}} = Catalog.curate()
      assert Repo.aggregate(Game, :count) == 4
    end

    test "prunes what nobody follows outside the criterion, never a library's game" do
      {:ok, user} = user_fixture()
      randomizer = game_fixture(%{title: @randomizer["name"], igdb_id: 331_139})
      {:ok, _} = entry_fixture(user, randomizer, %{purchase_intent: :want})
      junk = game_fixture(%{title: @zenge["name"], igdb_id: 250_004})
      typed = game_fixture(%{title: "Typed by hand"})

      assert {:ok, %{pruned: []}} = Catalog.curate()
      assert Repo.get(Game, junk.id)

      assert {:ok, report} = Catalog.curate(prune: true)
      assert report.kept == [@randomizer["name"]]
      assert report.pruned == [@zenge["name"]]
      refute Repo.get(Game, junk.id)
      assert Repo.get(Game, randomizer.id)
      assert Repo.get(Game, typed.id)
    end

    test "never prunes when the eShop ranking was not read" do
      junk = game_fixture(%{title: "Kitten Island", igdb_id: 250_001})
      Application.put_env(:dockd, :eshop, [])

      assert {:ok, %{pruned: [], eshop: :not_configured}} = Catalog.curate(prune: true)
      assert Repo.get(Game, junk.id)
    end
  end
end
