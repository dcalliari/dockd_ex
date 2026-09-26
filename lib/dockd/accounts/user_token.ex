defmodule Dockd.Accounts.UserToken do
  @moduledoc """
  Tokens that authenticate a user: browser sessions, magic links and the API token.

  Session tokens live in a signed cookie, so they are stored as is. Magic link and API
  tokens leave the server in clear text, so only their hash is stored and a database
  reader cannot use them.
  """
  use Ecto.Schema
  import Ecto.Query
  alias Dockd.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  @magic_link_validity_in_minutes 15
  @session_validity_in_days 14

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, Dockd.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Builds a session token for the signed session cookie."
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc "Query for the user of a session token younger than the session validity."
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc "Builds a magic link token bound to the user's current email."
  def build_email_token(user, context), do: build_hashed_token(user, context, user.email)

  @doc "Builds an API token. It does not expire; a new one replaces it."
  def build_api_token(user), do: build_hashed_token(user, "api", nil)

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{token: hashed_token, context: context, sent_to: sent_to, user_id: user.id}}
  end

  @doc "Query for `{user, token}` of a magic link issued in the last minutes to the same email."
  def verify_magic_link_token_query(token) do
    with {:ok, hashed_token} <- decode_and_hash(token) do
      query =
        from token in by_token_and_context_query(hashed_token, "login"),
          join: user in assoc(token, :user),
          where: token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
          where: token.sent_to == user.email,
          select: {user, token}

      {:ok, query}
    end
  end

  @doc "Query for the user of an API token."
  def verify_api_token_query(token) do
    with {:ok, hashed_token} <- decode_and_hash(token) do
      query =
        from token in by_token_and_context_query(hashed_token, "api"),
          join: user in assoc(token, :user),
          select: user

      {:ok, query}
    end
  end

  defp decode_and_hash(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} -> {:ok, :crypto.hash(@hash_algorithm, decoded_token)}
      :error -> :error
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
