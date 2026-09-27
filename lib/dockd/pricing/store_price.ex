defmodule Dockd.Pricing.StorePrice do
  @moduledoc """
  A store price over an interval: a new row only when the price, the discount or the
  sales status changes; otherwise the daily sync moves `last_seen_at` forward.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "store_prices" do
    field :regular_cents, :integer
    field :discount_cents, :integer
    field :discount_starts_at, :utc_datetime_usec
    field :discount_ends_at, :utc_datetime_usec
    field :currency, :string, default: "BRL"
    field :sales_status, :string
    field :first_seen_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    belongs_to :listing, Dockd.Pricing.StoreListing, type: :binary_id
  end

  @fields [
    :regular_cents,
    :discount_cents,
    :discount_starts_at,
    :discount_ends_at,
    :currency,
    :sales_status,
    :first_seen_at,
    :last_seen_at
  ]

  def changeset(price, attrs) do
    price
    |> cast(attrs, @fields)
    |> validate_required([:listing_id, :sales_status, :first_seen_at, :last_seen_at])
    |> validate_number(:regular_cents, greater_than_or_equal_to: 0)
    |> validate_number(:discount_cents, greater_than_or_equal_to: 0)
    |> assoc_constraint(:listing)
  end
end
