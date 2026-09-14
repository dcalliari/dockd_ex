defmodule Dockd.Wallet.StoreBalance do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "store_balances" do
    field :store, Ecto.Enum, values: [:eshop]
    field :amount_cents, :integer
    field :currency, :string, default: "BRL"
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
