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

  test "release requires platform and game" do
    errors = Release.changeset(%Release{}, %{})
    assert Keyword.has_key?(errors.errors, :platform)
    assert Keyword.has_key?(errors.errors, :game_id)
  end
end
