defmodule Dockd.Accounts do
  @moduledoc "User account operations."
  import Ecto.Query
  alias Dockd.Accounts.User
  alias Dockd.Repo
  @doc "Returns the single owner used by the MVP, creating it when absent."
  def default_owner do
    Repo.one(from u in User, order_by: [asc: u.inserted_at], limit: 1) ||
      case Repo.insert(User.changeset(%User{}, %{name: "Owner"})) do
        {:ok, user} -> user
        {:error, _} -> Repo.one!(User)
      end
  end

  @doc "Gets a user by id."
  def get_user!(id), do: Repo.get!(User, id)
  @doc "Creates a user."
  def create_user(attrs), do: %User{} |> User.changeset(attrs) |> Repo.insert()
end
