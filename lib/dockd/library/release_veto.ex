defmodule Dockd.Library.ReleaseVeto do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "release_vetoes" do
    field :reason, :string
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    belongs_to :release, Dockd.Catalog.Release, type: :binary_id
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(veto, attrs),
    do:
      veto
      |> cast(attrs, [:user_id, :release_id, :reason])
      |> validate_required([:user_id, :release_id])
end
