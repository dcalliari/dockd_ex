defmodule Dockd.Repo.Migrations.DropWalletAndRelaxPurchase do
  @moduledoc """
  The eShop balance and the reservations leave the product (decision of 27/09/2026): they
  depended on the user typing and correcting a balance by hand. Their rows are test data
  and go with the tables. A purchase no longer needs a price or a store: Comprei records
  it in one tap with the last seen price, which may not exist.
  """
  use Ecto.Migration

  def up do
    drop table(:balance_reservations)
    drop table(:store_balances)
    execute "DROP TYPE store"

    alter table(:purchases) do
      remove :store_credit_used_cents
      modify :price_cents, :integer, null: true
      modify :retailer, :text, null: true
    end
  end

  def down do
    execute "UPDATE purchases SET price_cents = 0 WHERE price_cents IS NULL"
    execute "UPDATE purchases SET retailer = '' WHERE retailer IS NULL"

    alter table(:purchases) do
      add :store_credit_used_cents, :integer, null: false, default: 0
      modify :price_cents, :integer, null: false
      modify :retailer, :text, null: false
    end

    execute "CREATE TYPE store AS ENUM ('eshop')"

    create table(:store_balances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :store, :store, null: false
      add :amount_cents, :integer, null: false
      add :currency, :text, null: false, default: "BRL"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:store_balances, [:user_id, :store])

    create table(:balance_reservations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :store, :store, null: false
      add :game_id, references(:games, type: :binary_id, on_delete: :delete_all), null: false
      add :amount_cents, :integer, null: false
      add :note, :text
      timestamps(type: :utc_datetime_usec)
    end
  end
end
