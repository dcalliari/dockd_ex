defmodule Dockd.Social.ProfileFavorite do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dockd.Accounts.User
  alias Dockd.Catalog.Game

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "profile_favorites" do
    field :position, :integer
    belongs_to :user, User, type: :binary_id
    belongs_to :game, Game, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:user_id, :game_id, :position])
    |> validate_required([:user_id, :game_id, :position])
    |> validate_number(:position, greater_than: 0)
    |> assoc_constraint(:user)
    |> assoc_constraint(:game)
    |> unique_constraint([:user_id, :game_id])
    |> unique_constraint([:user_id, :position])
  end
end
