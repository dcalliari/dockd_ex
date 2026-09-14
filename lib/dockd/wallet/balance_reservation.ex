defmodule Dockd.Wallet.BalanceReservation do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "balance_reservations" do
    field :store, Ecto.Enum, values: [:eshop]
    field :amount_cents, :integer
    field :note, :string
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    belongs_to :game, Dockd.Catalog.Game, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end
end
