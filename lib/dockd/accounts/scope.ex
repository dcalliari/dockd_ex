defmodule Dockd.Accounts.Scope do
  @moduledoc """
  Who is calling: assigned as `current_scope` by `DockdWeb.UserAuth` in the browser and
  in the API. It carries only the user, since an account is one library with no roles.
  """

  alias Dockd.Accounts.User

  defstruct user: nil

  @doc "Scope for a user; nil when signed out."
  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
