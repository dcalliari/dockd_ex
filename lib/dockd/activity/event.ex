defmodule Dockd.Activity.Event do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "events" do
    field :type, Ecto.Enum,
      values: [
        :added,
        :intent_changed,
        :purchased,
        :started,
        :paused,
        :resumed,
        :finished,
        :abandoned,
        :backlogged,
        :activated,
        :vetoed
      ]

    field :occurred_at, :utc_datetime_usec
    field :payload, :map, default: %{}
    belongs_to :user, Dockd.Accounts.User, type: :binary_id
    belongs_to :game, Dockd.Catalog.Game, type: :binary_id
    belongs_to :release, Dockd.Catalog.Release, type: :binary_id
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:user_id, :game_id, :release_id, :type, :occurred_at, :payload])
    |> validate_required([:user_id, :type, :occurred_at])
  end
end
