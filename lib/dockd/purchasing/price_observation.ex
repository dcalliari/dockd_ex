defmodule Dockd.Purchasing.PriceObservation do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "price_observations" do
    field :format, Ecto.Enum, values: [:physical, :digital]
    field :price_cents, :integer
    field :currency, :string, default: "BRL"
    field :observed_at, :utc_datetime_usec
    field :source, :string
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    belongs_to :release, Dockd.Catalog.Release, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(observation, attrs),
    do:
      observation
      |> cast(attrs, [
        :user_id,
        :release_id,
        :format,
        :price_cents,
        :currency,
        :observed_at,
        :source
      ])
      |> validate_required([:user_id, :release_id, :format, :price_cents, :observed_at, :source])
      |> validate_number(:price_cents, greater_than_or_equal_to: 0)
end
