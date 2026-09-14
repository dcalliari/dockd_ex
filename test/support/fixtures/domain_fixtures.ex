defmodule Dockd.DomainFixtures do
  alias Dockd.{Accounts, Catalog, Library, Purchasing, Wallet}

  @doc "Creates the default owner for context tests."
  def user_fixture(attrs \\ %{}), do: Accounts.create_user(Map.merge(%{name: "Test owner"}, attrs))
  @doc "Creates a catalog game for context tests."
  def game_fixture(attrs \\ %{}) do
    {:ok, game} = Catalog.create_game(Map.merge(%{title: "Test game", availability: :nintendo_exclusive}, attrs))
    game
  end
  @doc "Creates a release for a game."
  def release_fixture(game, attrs \\ %{}) do
    {:ok, release} = Catalog.create_release(game.id, Map.merge(%{platform: :switch, digital_available: true}, attrs))
    release
  end
  @doc "Creates a library entry."
  def entry_fixture(user, game, attrs \\ %{}) do
    Library.create_entry(user, Map.merge(%{game_id: game.id}, attrs))
  end
  @doc "Creates a purchase."
  def purchase_fixture(user, release, attrs \\ %{}) do
    Purchasing.create_purchase(user, Map.merge(%{release_id: release.id, format: :digital, price_cents: 1000, purchased_at: DateTime.utc_now(), retailer: "eShop"}, attrs))
  end
  @doc "Creates an eShop balance."
  def balance_fixture(user, attrs \\ %{}), do: Wallet.create_balance(user, Map.merge(%{store: :eshop, amount_cents: 1000}, attrs))
end
