defmodule Dockd.Pricing.StoreListing do
  @moduledoc """
  A release as a store sells it: the eShop Brasil product (nsuid) for one platform.

  `match` says how the product was chosen: `:auto` and `:confirmed` are priced daily,
  `:review` waits for a person to pick one of the `candidates`, `:rejected` means the
  store does not sell this release.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "store_listings" do
    field :store, Ecto.Enum, values: [:eshop_br]
    field :external_id, :string
    field :title, :string
    field :match, Ecto.Enum, values: [:auto, :confirmed, :review, :rejected]
    field :candidates, {:array, :map}, default: []
    field :sales_status, :string
    field :checked_at, :utc_datetime_usec
    belongs_to :release, Dockd.Catalog.Release, type: :binary_id
    has_many :prices, Dockd.Pricing.StorePrice, foreign_key: :listing_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(listing, attrs) do
    listing
    |> cast(attrs, [:store, :external_id, :title, :match, :candidates, :sales_status, :checked_at])
    |> validate_required([:release_id, :store, :match])
    |> validate_external_id()
    |> assoc_constraint(:release)
    |> unique_constraint([:store, :external_id], error_key: :external_id)
    |> unique_constraint([:release_id, :store])
  end

  defp validate_external_id(changeset) do
    if get_field(changeset, :match) in [:auto, :confirmed],
      do: validate_required(changeset, [:external_id]),
      else: changeset
  end
end
