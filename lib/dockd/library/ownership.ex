defmodule Dockd.Library.Ownership do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "ownerships" do
    field :ownership_type, Ecto.Enum,
      values: [:physical, :digital, :subscription, :shared, :borrowed]

    field :acquired_at, :utc_datetime_usec
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    belongs_to :release, Dockd.Catalog.Release, type: :binary_id
    belongs_to :purchase, Dockd.Purchasing.Purchase, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(ownership, attrs),
    do:
      ownership
      |> cast(attrs, [:user_id, :release_id, :ownership_type, :acquired_at, :purchase_id])
      |> validate_required([:user_id, :release_id, :ownership_type, :acquired_at])
end
