defmodule Dockd.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :name, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(user, attrs),
    do:
      user |> cast(attrs, [:name]) |> validate_required([:name]) |> validate_length(:name, min: 1)
end
