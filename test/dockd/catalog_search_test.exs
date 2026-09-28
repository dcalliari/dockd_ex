defmodule Dockd.CatalogSearchTest do
  use Dockd.DataCase, async: true
  import Dockd.DomainFixtures
  alias Dockd.Catalog

  defp titles(results), do: Enum.map(results, & &1.title)

  describe "search/1" do
    test "finds the catalog by title or alternative name, the most rated first" do
      botw = game_fixture(%{title: "The Legend of Zelda: Breath of the Wild", rating_count: 3006})
      release_fixture(botw, %{platform: :switch, release_date: ~D[2017-03-03]})

      cadence =
        game_fixture(%{
          title: "Cadence of Hyrule",
          alternative_names: ["Cadence of Hyrule: Crypt of the NecroDancer Featuring Zelda"],
          rating_count: 61
        })

      game_fixture(%{title: "Pokémon Legends: Z-A", rating_count: 200})
      game_fixture(%{title: "Metroid Dread"})

      assert [first, second] = Catalog.search("ZELDA")
      assert first.game.id == botw.id and first.year == 2017 and first.platforms == [:switch]
      assert second.game.id == cadence.id

      # No accent, case or punctuation stands in the way.
      assert titles(Catalog.search("pokemon legends za")) == ["Pokémon Legends: Z-A"]
      assert Catalog.search("  ") == []
      assert Catalog.search("%") == []
    end

    test "a query never matches across two names" do
      game_fixture(%{title: "Alpha", alternative_names: ["Beta"]})

      assert titles(Catalog.search("beta")) == ["Alpha"]
      assert Catalog.search("alpha beta") == []
    end
  end

  test "two games of the same title keep their slugs through an update" do
    game_fixture(%{title: "Trials of Mana", slug: "trials-of-mana"})
    remake = game_fixture(%{title: "Trials of Mana", slug: "trials-of-mana--1"})

    assert {:ok, %{slug: "trials-of-mana--1"}} = Catalog.update_game(remake, %{hypes: 3})

    assert {:ok, %{slug: "seiken-densetsu-3"}} =
             Catalog.update_game(remake, %{title: "Seiken Densetsu 3"})
  end

  describe "showcase/1" do
    setup do
      today = Date.utc_today()

      coming = game_fixture(%{title: "Coming soon"})
      release_fixture(coming, %{platform: :switch_2, release_date: Date.add(today, 30)})

      this_year =
        game_fixture(%{title: "Sometime this year"})

      release_fixture(this_year, %{
        platform: :switch,
        release_date: Date.new!(today.year + 1, 1, 1),
        release_date_precision: :year
      })

      fresh = game_fixture(%{title: "Fresh", rating_count: 10})
      release_fixture(fresh, %{platform: :switch, release_date: Date.add(today, -10)})

      loved = game_fixture(%{title: "Loved", rating_count: 500, hypes: 20})
      release_fixture(loved, %{platform: :switch, release_date: Date.add(today, -60)})

      last_year = game_fixture(%{title: "Last spring", rating_count: 900})
      release_fixture(last_year, %{platform: :switch, release_date: Date.add(today, -200)})

      old = game_fixture(%{title: "Old", rating_count: 5000})
      release_fixture(old, %{platform: :switch, release_date: ~D[2017-03-03]})
      :ok
    end

    test "upcoming: the ones dated to the day first, soonest first" do
      assert titles(Catalog.showcase(:upcoming)) == ["Coming soon", "Sometime this year"]
    end

    test "recent and popular: out in the window, the most rated first" do
      assert titles(Catalog.showcase(:recent)) == ["Loved", "Fresh"]
      assert titles(Catalog.showcase(:popular)) == ["Last spring", "Loved", "Fresh"]
    end
  end
end
