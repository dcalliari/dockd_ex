defmodule Dockd.DomainFixtures do
  @moduledoc "Fixtures for domain context tests."
  alias Dockd.Accounts.User
  alias Dockd.{Catalog, Library, Purchasing}
  alias Dockd.Pricing.{StoreListing, StorePrice}

  @doc "Creates a library owner for context tests; the domain does not need a login."
  def user_fixture(attrs \\ %{}),
    do: Dockd.Repo.insert(%User{name: Map.get(attrs, :name, "Test owner")})

  @doc "Creates a catalog game for context tests."
  def game_fixture(attrs \\ %{}) do
    {:ok, game} =
      Catalog.create_game(
        Map.merge(%{title: "Test game", availability: :nintendo_exclusive}, attrs)
      )

    game
  end

  @doc "Creates a release for a game."
  def release_fixture(game, attrs \\ %{}) do
    {:ok, release} =
      Catalog.create_release(
        game.id,
        Map.merge(%{platform: :switch, digital_available: true}, attrs)
      )

    release
  end

  @doc "Creates a library entry."
  def entry_fixture(user, game, attrs \\ %{}) do
    Library.create_entry(user, Map.merge(%{game_id: game.id}, attrs))
  end

  @doc "Creates a purchase."
  def purchase_fixture(user, release, attrs \\ %{}) do
    Purchasing.create_purchase(
      user,
      Map.merge(
        %{
          release_id: release.id,
          format: :digital,
          price_cents: 1000,
          purchased_at: DateTime.utc_now(),
          retailer: "eShop"
        },
        attrs
      )
    )
  end

  @doc "Lists a release on the eShop Brasil with a price seen now, as the daily sync would."
  def store_price_fixture(release, attrs \\ %{}) do
    now = DateTime.utc_now()

    listing =
      %StoreListing{release_id: release.id}
      |> StoreListing.changeset(%{
        store: :eshop_br,
        match: :auto,
        external_id: "7001#{System.unique_integer([:positive])}",
        sales_status: Map.get(attrs, :sales_status, "onsale")
      })
      |> Dockd.Repo.insert!()

    %StorePrice{listing_id: listing.id}
    |> StorePrice.changeset(
      Map.merge(
        %{regular_cents: 38_990, sales_status: "onsale", first_seen_at: now, last_seen_at: now},
        attrs
      )
    )
    |> Dockd.Repo.insert!()
  end
end
