defmodule Dockd.Accounts.User do
  @moduledoc "An account. Each account is one library."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Changeset for an email and a password: a new account, or the owner row that
  predates accounts. The name shown in the navigation comes from the email, since
  there is no profile to edit.

  Pass `validate_unique: false` to skip the database lookup on live validation.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
    |> put_name_from_email()
  end

  @doc "Changeset for replacing the password."
  def password_changeset(user, attrs),
    do: user |> cast(attrs, [:password]) |> validate_password([])

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> update_change(:email, &String.trim/1)
      |> validate_required([:email], message: "Informe o e-mail")
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/, message: "E-mail inválido")
      |> validate_length(:email, max: 160, message: "E-mail longo demais")

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Dockd.Repo, message: "E-mail já tem conta")
      |> unique_constraint(:email, message: "E-mail já tem conta")
    else
      changeset
    end
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password], message: "Informe a senha")
    |> validate_length(:password, min: 12, max: 72, message: "Mínimo de 12 caracteres")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    password = get_change(changeset, :password)

    if Keyword.get(opts, :hash_password, true) && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp put_name_from_email(changeset) do
    case get_change(changeset, :email) do
      nil ->
        changeset

      email ->
        put_change(changeset, :name, email |> String.split("@") |> hd() |> String.capitalize())
    end
  end

  @doc "Confirms the account: its email received a magic link and it was used."
  def confirm_changeset(user), do: change(user, confirmed_at: DateTime.utc_now(:second))

  @doc """
  Verifies the password. Without a user or a password it still spends the hashing time,
  so the response does not reveal whether the email has an account.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Pbkdf2.no_user_verify()
    false
  end
end
