defmodule Dockd.Accounts do
  alias Dockd.{Repo, Accounts.User}
  @doc "Returns the single owner used by the MVP, creating it when absent."
  def default_owner do
    Repo.one(User) || case Repo.insert(User.changeset(%User{}, %{name: "Owner"})) do
      {:ok, user} -> user
      {:error, _} -> Repo.one!(User)
    end
  end
  @doc "Gets a user by id."
  def get_user!(id), do: Repo.get!(User, id)
  @doc "Creates a user."
  def create_user(attrs), do: %User{} |> User.changeset(attrs) |> Repo.insert()
end
