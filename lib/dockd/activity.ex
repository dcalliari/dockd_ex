defmodule Dockd.Activity do
  import Ecto.Query
  alias Dockd.{Repo, Accounts.User}
  alias Dockd.Activity.Event
  @doc "Lists a user's events, newest first."
  def list_events(%User{id: id}), do: Repo.all(from e in Event, where: e.user_id == ^id, order_by: [desc: e.occurred_at])
  @doc "Appends an event to a transaction."
  def append(multi, attrs), do: Ecto.Multi.insert(multi, {:event, System.unique_integer([:positive])}, Event.changeset(%Event{}, attrs))
  @doc "Builds an event changeset."
  def changeset(event, attrs), do: event |> Ecto.Changeset.cast(attrs, [:user_id, :game_id, :release_id, :type, :occurred_at, :payload]) |> Ecto.Changeset.validate_required([:user_id, :type, :occurred_at])
end
