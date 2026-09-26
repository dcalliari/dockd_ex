defmodule Dockd.AccountsFixtures do
  @moduledoc "Test helpers for `Dockd.Accounts`."

  import Ecto.Query

  alias Dockd.Accounts
  alias Dockd.Accounts.{Scope, UserToken}

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}),
    do: Enum.into(attrs, %{email: unique_user_email(), password: valid_user_password()})

  def user_fixture(attrs \\ %{}) do
    {:ok, user} = attrs |> valid_user_attributes() |> Accounts.register_user()
    user
  end

  def user_scope_fixture(user \\ user_fixture()), do: Scope.for_user(user)

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Dockd.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Dockd.Repo.update_all(
      from(t in UserToken, where: t.token == ^token),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Dockd.Repo.update_all(
      from(ut in UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
