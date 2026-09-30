defmodule Dockd.CatalogTest do
  use Dockd.DataCase, async: true
  alias Dockd.Catalog
  alias Dockd.Catalog.{Game, Release}

  test "game changeset generates slug and validates catalog labels" do
    changeset =
      Game.changeset(%Game{}, %{
        title: "Mario Kart: World",
        availability: :multiplatform,
        other_platforms: ["PC"],
        estimated_duration_minutes: 0
      })

    refute changeset.valid?
    assert changeset.errors[:estimated_duration_minutes]
    assert Ecto.Changeset.get_field(changeset, :slug) == "mario-kart-world"

    assert Game.changeset(%Game{}, %{
             title: "Zelda",
             availability: :nintendo_exclusive,
             other_platforms: ["PC"]
           }).errors[:other_platforms]
  end

  test "catalog creates and lists games and releases" do
    {:ok, game} = Catalog.create_game(%{title: "Kirby", availability: :nintendo_exclusive})

    {:ok, release} =
      Catalog.create_release(game.id, %{platform: :switch, physical_available: true})

    assert Catalog.get_game!(game.id).title == "Kirby"
    assert hd(Catalog.list_releases(game.id)).id == release.id
  end

  test "deletes an unused release" do
    {:ok, game} = Catalog.create_game(%{title: "Sports Resort", availability: :switch2_exclusive})
    {:ok, release} = Catalog.create_release(game.id, %{platform: :switch})

    assert {:ok, _deleted} = Catalog.delete_release(release)
    assert_raise Ecto.NoResultsError, fn -> Catalog.get_release!(game.id, release.id) end
  end

  test "refuses to delete a release with ownership" do
    {:ok, game} = Catalog.create_game(%{title: "Owned game", availability: :nintendo_exclusive})
    {:ok, release} = Catalog.create_release(game.id, %{platform: :switch})
    {:ok, user} = Dockd.DomainFixtures.user_fixture()

    assert {:ok, _ownership} =
             Dockd.Library.create_ownership(user, %{
               release_id: release.id,
               ownership_type: :digital,
               acquired_at: DateTime.utc_now()
             })

    assert {:error, {:in_use, [:ownership]}} = Catalog.delete_release(release)
  end

  describe "confirm_physical_available/1" do
    test "turns the flag on once, and repeating it changes nothing" do
      {:ok, game} = Catalog.create_game(%{title: "Owned game", availability: :nintendo_exclusive})
      {:ok, release} = Catalog.create_release(game.id, %{platform: :switch})

      assert {1, _} = Catalog.confirm_physical_available(release.id)
      assert Catalog.get_release!(game.id, release.id).physical_available

      assert {0, _} = Catalog.confirm_physical_available(release.id)
    end

    test "never turns a digital-only release physical without evidence" do
      {:ok, game} = Catalog.create_game(%{title: "Indie", availability: :nintendo_exclusive})
      {:ok, release} = Catalog.create_release(game.id, %{platform: :switch})

      refute release.physical_available
    end
  end

  describe "backfill_physical_available/0" do
    test "confirms every release with a prior physical ownership or price observation" do
      {:ok, game} =
        Catalog.create_game(%{title: "Backfill game", availability: :nintendo_exclusive})

      {:ok, owned} = Catalog.create_release(game.id, %{platform: :switch})
      {:ok, priced} = Catalog.create_release(game.id, %{platform: :switch_2})
      {:ok, untouched} = Catalog.create_release(game.id, %{platform: :switch, edition: "Deluxe"})
      {:ok, user} = Dockd.DomainFixtures.user_fixture()

      # Inserted directly, as if recorded before physical_available was evidence-based,
      # so the backfill (not the live create_ownership/create_price_observation) is what
      # confirms them.
      Dockd.Repo.insert!(%Dockd.Library.Ownership{
        user_id: user.id,
        release_id: owned.id,
        ownership_type: :physical,
        acquired_at: DateTime.utc_now()
      })

      Dockd.Repo.insert!(%Dockd.Purchasing.PriceObservation{
        user_id: user.id,
        release_id: priced.id,
        format: :physical,
        price_cents: 29_990,
        observed_at: DateTime.utc_now(),
        source: "Amazon"
      })

      assert Catalog.backfill_physical_available() == 2

      assert Catalog.get_release!(game.id, owned.id).physical_available
      assert Catalog.get_release!(game.id, priced.id).physical_available
      refute Catalog.get_release!(game.id, untouched.id).physical_available

      assert Catalog.backfill_physical_available() == 0
    end
  end

  describe "Release.launch/3" do
    test "a date known by year, quarter or month is out only once the period is over" do
      year = %Release{release_date: ~D[2026-01-01], release_date_precision: :year}
      quarter = %Release{release_date: ~D[2026-07-01], release_date_precision: :quarter}
      month = %Release{release_date: ~D[2026-09-01], release_date_precision: :month}

      assert Release.launch(year, ~D[2026-09-28]) == :upcoming
      assert Release.launch(year, ~D[2026-12-31]) == :released
      assert Release.launch(quarter, ~D[2026-09-28]) == :upcoming
      assert Release.launch(quarter, ~D[2026-09-30]) == :released
      assert Release.launch(month, ~D[2026-09-28]) == :upcoming
      assert Release.launch(month, ~D[2026-10-01]) == :released
    end

    test "a day date is out on the day" do
      release = %Release{release_date: ~D[2026-11-05], release_date_precision: :day}

      assert Release.launch(release, ~D[2026-11-04]) == :upcoming
      assert Release.launch(release, ~D[2026-11-05]) == :released
    end

    test "the eShop holds back a release it has not released, whatever the date says" do
      past = %Release{release_date: ~D[2026-01-01], release_date_precision: :day}

      assert Release.launch(past, ~D[2026-09-28], "unreleased") == :upcoming
      assert Release.launch(past, ~D[2026-09-28], "preorder") == :upcoming
      assert Release.launch(%Release{}, ~D[2026-09-28], "unreleased") == :undated
    end

    test "without a date, a release is out only when the eShop sells or sold it" do
      assert Release.launch(%Release{}, ~D[2026-09-28]) == :undated
      assert Release.launch(%Release{}, ~D[2026-09-28], "onsale") == :released
      assert Release.launch(%Release{}, ~D[2026-09-28], "sales_termination") == :released
    end
  end

  describe "Release.igdb_launched?/2" do
    test "a date known only by year, quarter or month is launched once the period is over" do
      year = [%{"date" => 1_767_225_600, "date_format" => 2}]
      assert Release.igdb_launched?(year, ~D[2026-09-28]) == false
      assert Release.igdb_launched?(year, ~D[2026-12-31]) == true
    end

    test "a day date is launched on the day" do
      day = [%{"date" => 1_793_836_800, "date_format" => 0}]
      assert Release.igdb_launched?(day, ~D[2026-11-04]) == false
      assert Release.igdb_launched?(day, ~D[2026-11-05]) == true
    end

    test "TBD or no date is never launched by the date alone" do
      assert Release.igdb_launched?([], ~D[2026-09-28]) == false
      assert Release.igdb_launched?([%{"date" => 1_767_225_600, "date_format" => 7}]) == false
    end
  end

  test "release key card is castable" do
    changeset =
      Release.changeset(%Release{game_id: Ecto.UUID.generate()}, %{
        platform: :switch,
        physical_is_key_card: true
      })

    assert Ecto.Changeset.get_change(changeset, :physical_is_key_card) == true
  end

  test "release requires platform and game" do
    errors = Release.changeset(%Release{}, %{})
    assert Keyword.has_key?(errors.errors, :platform)
    assert Keyword.has_key?(errors.errors, :game_id)
  end
end
