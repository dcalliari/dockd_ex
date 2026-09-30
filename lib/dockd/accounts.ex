defmodule Dockd.Accounts do
  @moduledoc "Accounts: registration, sign-in by password or magic link, sessions and API tokens."
  import Ecto.Query
  alias Dockd.Accounts.{User, UserNotifier, UserToken}
  alias Dockd.Repo

  @doc "Gets a user by id."
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a user by email."
  def get_user_by_email(email) when is_binary(email), do: Repo.get_by(User, email: email)

  @doc "Promotes or demotes an account by email."
  def set_admin(email, admin) when is_binary(email) and is_boolean(admin) do
    case get_user_by_email(email) do
      nil -> {:error, :not_found}
      user -> user |> Ecto.Changeset.change(admin: admin) |> Repo.update()
    end
  end

  @doc "Gets a user by email and password, or nil."
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc "Registers an account with email and password."
  def register_user(attrs), do: %User{} |> User.registration_changeset(attrs) |> Repo.insert()

  @doc "Changeset for the registration form."
  def change_user_registration(user, attrs \\ %{}, opts \\ []),
    do: User.registration_changeset(user, attrs, opts)

  @doc "Changeset for the account's public identity."
  def change_user_profile(user, attrs \\ %{}, opts \\ []),
    do: User.profile_changeset(user, attrs, opts)

  @doc "Updates the account's public identity."
  def update_user_profile(user, attrs), do: user |> User.profile_changeset(attrs) |> Repo.update()

  @doc "Changeset for an email change before its confirmation email is sent."
  def change_user_email(user, attrs \\ %{}, opts \\ []),
    do: User.email_changeset(user, attrs, opts)

  @doc "Changeset for a password change before verifying the current password."
  def change_user_password(user, attrs \\ %{}), do: User.password_changeset(user, attrs)

  @doc """
  Gives the owner, the oldest user and the one that predates accounts, an email and a
  password, so the library it already has becomes a normal account.
  """
  def claim_owner(email, password) do
    case Repo.one(from u in User, order_by: [asc: u.inserted_at], limit: 1) do
      %User{email: nil} = owner ->
        owner |> User.registration_changeset(%{email: email, password: password}) |> Repo.update()

      %User{} ->
        {:error, :already_claimed}

      nil ->
        {:error, :no_owner}
    end
  end

  @doc "Replaces the password of the account with this email and ends its sessions."
  def reset_password(email, password) do
    case get_user_by_email(email) do
      nil -> {:error, :not_found}
      user -> update_user_password(user, %{password: password})
    end
  end

  @doc "Updates the password and expires every token of the user. Returns the expired tokens."
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc "Updates a password after checking the current one, keeping this browser session alive."
  def update_user_password_with_current(user, current_password, attrs, current_token) do
    if User.valid_password?(user, current_password) do
      user
      |> User.password_changeset(attrs)
      |> update_user_and_delete_all_tokens(current_token)
    else
      {:error, :current_password}
    end
  end

  ## Session

  @doc "Lists active browser sessions, newest first."
  def list_user_sessions(%User{id: user_id}) do
    Repo.all(
      from token in UserToken,
        where: token.user_id == ^user_id and token.context == "session",
        order_by: [desc: token.inserted_at]
    )
  end

  @doc "Ends every browser session except the current raw session token."
  def delete_other_user_sessions(%User{id: user_id}, current_token)
      when is_binary(current_token) do
    tokens =
      Repo.all(
        from token in UserToken,
          where:
            token.user_id == ^user_id and token.context == "session" and
              token.token != ^current_token
      )

    Repo.delete_all(from token in UserToken, where: token.id in ^Enum.map(tokens, & &1.id))
    tokens
  end

  def delete_other_user_sessions(%User{}, _current_token), do: []

  @doc "Generates a session token."
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Gets `{user, token_inserted_at}` for a valid session token, or nil."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes a session token."
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Email change and magic link

  @doc "Sends a confirmation link to a new email without changing the account yet."
  def deliver_user_email_change_instructions(%User{} = user, attrs, url_fun)
      when is_function(url_fun, 1) do
    changeset = User.email_changeset(user, attrs)

    with true <- magic_link_enabled?(),
         true <- changeset.valid?,
         email <- Ecto.Changeset.get_field(changeset, :email),
         {encoded_token, user_token} <- UserToken.build_email_change_token(user, email),
         {_, _} <-
           Repo.delete_all(
             from token in UserToken,
               where: token.user_id == ^user.id and like(token.context, "change:%")
           ),
         {:ok, _} <- Repo.insert(user_token) do
      UserNotifier.deliver_email_change_instructions(user, email, url_fun.(encoded_token))
    else
      false when not changeset.valid? -> {:error, changeset}
      false -> {:error, :magic_link_disabled}
      {:error, _} = error -> error
    end
  end

  @doc "Confirms a new email with its one-time token."
  def update_user_email_by_token(token) do
    with {:ok, query} <- UserToken.verify_email_change_token_query(token),
         {user, user_token} <- Repo.one(query) do
      Repo.transact(fn -> apply_confirmed_email(user, user_token) end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp apply_confirmed_email(user, user_token) do
    with {:ok, user} <-
           user
           |> User.email_changeset(%{email: user_token.sent_to})
           |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
           |> Repo.update(),
         {:ok, _} <- Repo.delete(user_token) do
      {:ok, user}
    end
  end

  ## Magic link

  @doc """
  Whether sign-in by link is offered. It depends only on configuration: in production
  it turns on when the SMTP variables exist (see `config/runtime.exs`).
  """
  def magic_link_enabled?, do: Application.get_env(:dockd, :magic_link, false)

  @doc "Sends a sign-in link, when links are enabled."
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    if magic_link_enabled?() do
      {encoded_token, user_token} = UserToken.build_email_token(user, "login")
      Repo.insert!(user_token)
      UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
    else
      {:error, :magic_link_disabled}
    end
  end

  @doc "Gets the user of a magic link token, or nil."
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Signs in by magic link. Returns `{:ok, {user, expired_tokens}}`.

  The first link used confirms the email. Accounts are created with a password and no
  email check, so whoever registered an email may not own it: on confirmation the
  password is discarded and every token expires, leaving the account to the email's
  owner. The password can be set again with `Dockd.Release.reset_password/2`.
  """
  def login_user_by_magic_link(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, user_token} <- Repo.one(query) do
      case user do
        %User{confirmed_at: nil} ->
          user
          |> User.confirm_changeset()
          |> Ecto.Changeset.put_change(:hashed_password, nil)
          |> update_user_and_delete_all_tokens()

        _ ->
          Repo.delete!(user_token)
          {:ok, {user, []}}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  ## Data

  @doc "Returns the account's personal data in a JSON-ready map, without credentials."
  def export_user_data(%User{} = user) do
    alias Dockd.Activity.Event
    alias Dockd.Library.{Entry, Ownership, ReleaseVeto}
    alias Dockd.Purchasing.{PriceObservation, Purchase}
    alias Dockd.Social.Follow

    %{
      exported_at: DateTime.utc_now(:second) |> DateTime.to_iso8601(),
      profile:
        export_record(user, [
          :id,
          :name,
          :username,
          :email,
          :profile_visibility,
          :confirmed_at,
          :inserted_at
        ]),
      entries: export_records(Entry, user.id),
      ownerships: export_records(Ownership, user.id),
      purchases: export_records(Purchase, user.id),
      price_observations: export_records(PriceObservation, user.id),
      vetoes: export_records(ReleaseVeto, user.id),
      events: export_records(Event, user.id),
      follows: export_follow_records(user.id, Follow)
    }
  end

  @doc "Deletes the account and returns the tokens whose LiveViews must disconnect."
  def delete_user(%User{} = user) do
    Repo.transact(fn ->
      tokens = Repo.all_by(UserToken, user_id: user.id)

      with {:ok, _} <- Repo.delete(user) do
        {:ok, tokens}
      end
    end)
  end

  defp export_records(schema, user_id) do
    schema
    |> Repo.all_by(user_id: user_id)
    |> Enum.map(&export_record(&1, schema.__schema__(:fields)))
  end

  defp export_follow_records(user_id, follow_schema) do
    Repo.all(
      from follow in follow_schema,
        where: follow.follower_id == ^user_id or follow.followed_id == ^user_id
    )
    |> Enum.map(&export_record(&1, follow_schema.__schema__(:fields)))
  end

  defp export_record(record, fields) do
    Map.new(fields, fn field -> {field, export_value(Map.get(record, field))} end)
  end

  defp export_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp export_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp export_value(value) when is_atom(value), do: Atom.to_string(value)

  defp export_value(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, export_value(value)} end)

  defp export_value(value) when is_list(value), do: Enum.map(value, &export_value/1)
  defp export_value(value), do: value

  ## API

  @doc "Creates the user's API token, replacing the previous one. Returns the token in clear."
  def create_api_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_api_token(user)

    Repo.transact(fn ->
      Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: "api"]))
      Repo.insert!(user_token)
      {:ok, encoded_token}
    end)
  end

  @doc "Gets the user of an API token, or nil."
  def get_user_by_api_token(token) when is_binary(token) do
    case UserToken.verify_api_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  defp update_user_and_delete_all_tokens(changeset, current_token \\ nil) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire =
          Repo.all_by(UserToken, user_id: user.id)
          |> Enum.reject(&(&1.context == "session" and &1.token == current_token))

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))
        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
