defmodule Dockd.Repo.Migrations.CreateStoreListingsAndPrices do
  use Ecto.Migration

  # A store price is catalog data, the same for every account; the user's own
  # price_observations stay user scoped.
  def change do
    execute "CREATE TYPE listing_store AS ENUM ('eshop_br')", "DROP TYPE listing_store"

    execute "CREATE TYPE listing_match AS ENUM ('auto', 'confirmed', 'review', 'rejected')",
            "DROP TYPE listing_match"

    create table(:store_listings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :release_id, references(:releases, type: :binary_id, on_delete: :delete_all),
        null: false

      add :store, :listing_store, null: false
      # nsuid on the eShop; empty while the match waits for review or was rejected
      add :external_id, :text
      add :title, :text
      add :match, :listing_match, null: false
      add :candidates, :jsonb, null: false, default: "[]"
      add :sales_status, :text
      add :checked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:store_listings, [:store, :external_id])
    create unique_index(:store_listings, [:release_id, :store])

    create table(:store_prices, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :listing_id, references(:store_listings, type: :binary_id, on_delete: :delete_all),
        null: false

      add :regular_cents, :integer
      add :discount_cents, :integer
      add :discount_starts_at, :utc_datetime_usec
      add :discount_ends_at, :utc_datetime_usec
      add :currency, :text, null: false, default: "BRL"
      add :sales_status, :text, null: false
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
    end

    create index(:store_prices, [:listing_id, :first_seen_at])
  end
end
