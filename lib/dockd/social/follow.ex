defmodule Dockd.Social.Follow do
  @moduledoc "One account following another. Two follows in opposite directions make friends."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "follows" do
    belongs_to :follower, Dockd.Accounts.User
    belongs_to :followed, Dockd.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:follower_id, :followed_id])
    |> validate_required([:follower_id, :followed_id])
    |> check_constraint(:followed_id, name: :not_self)
    |> unique_constraint([:follower_id, :followed_id])
  end
end
