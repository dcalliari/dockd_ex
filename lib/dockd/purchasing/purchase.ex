defmodule Dockd.Purchasing.Purchase do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "purchases" do
    field :format, Ecto.Enum, values: [:physical, :digital]
    field :price_cents, :integer
    field :currency, :string, default: "BRL"
    field :store_credit_used_cents, :integer, default: 0
    field :purchased_at, :utc_datetime_usec
    field :is_preorder, :boolean, default: false
    field :retailer, :string
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    belongs_to :release, Dockd.Catalog.Release, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end
  def changeset(purchase, attrs), do: purchase |> cast(attrs, [:user_id, :release_id, :format, :price_cents, :currency, :store_credit_used_cents, :purchased_at, :is_preorder, :retailer]) |> validate_required([:user_id, :release_id, :format, :price_cents, :purchased_at, :retailer]) |> validate_number(:price_cents, greater_than_or_equal_to: 0)
end
