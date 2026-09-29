defmodule Dockd.Accounts.User do
  @moduledoc "An account. Each account is one library."
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :name, :string
    field :email, :string
    field :admin, :boolean, default: false
    field :username, :string
    field :profile_visibility, Ecto.Enum, values: [:public, :friends], default: :public
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Changeset for an email and a password: a new account, or the owner row that
  predates accounts. The name shown in the navigation and the username in the profile
  address (`/u/:username`) come from the email, so there is no field to fill.

  Pass `validate_unique: false` to skip the database lookups on live validation.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    changeset =
      user
      |> cast(attrs, [:email, :password])
      |> validate_email(opts)
      |> validate_password(opts)
      |> put_name_from_email()

    if Keyword.get(opts, :validate_unique, true), do: put_username(changeset), else: changeset
  end

  @doc "Changeset for who sees the profile: everyone, or only friends."
  def visibility_changeset(user, visibility),
    do:
      user
      |> cast(%{profile_visibility: visibility}, [:profile_visibility])
      |> validate_required([:profile_visibility])

  @doc "Changeset for the display name, shown in the navigation."
  def name_changeset(user, attrs) do
    user
    |> cast(attrs, [:name])
    |> update_change(:name, &trim/1)
    |> validate_required([:name], message: "Informe o nome")
    |> validate_length(:name, max: 60, message: "Nome longo demais")
  end

  @doc """
  Changeset for the username, which is also the profile address (`/u/:username`).

  Pass `validate_unique: false` to skip the database lookup on live validation.
  """
  def username_changeset(user, attrs, opts \\ []) do
    changeset =
      user
      |> cast(attrs, [:username])
      |> update_change(:username, &trim/1)
      |> validate_required([:username], message: "Informe o nome de usuário")
      |> validate_format(:username, ~r/^[a-z0-9]+$/, message: "Só letras minúsculas e números")
      |> validate_length(:username, max: 30, message: "Nome de usuário longo demais")

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:username, Dockd.Repo, message: "Nome de usuário já existe")
      |> unique_constraint(:username, message: "Nome de usuário já existe")
    else
      changeset
    end
  end

  @doc """
  Changeset for the email. The current password is checked separately, by
  `Dockd.Accounts.update_user_email/3`, before this changeset applies.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user |> cast(attrs, [:email]) |> validate_email(opts)
  end

  @doc """
  The username an email suggests: the part before the at sign, lowercase, without
  accents or symbols, up to 30 characters; `conta` when nothing is left.
  """
  def username_base(email) do
    email
    |> String.split("@")
    |> hd()
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[^a-z0-9]/, "")
    |> String.slice(0, 30)
    |> case do
      "" -> "conta"
      base -> base
    end
  end

  defp put_username(%{data: %{username: nil}} = changeset) do
    case get_change(changeset, :email) do
      nil ->
        changeset

      email ->
        changeset
        |> put_change(:username, free_username(username_base(email)))
        |> unique_constraint(:username)
    end
  end

  defp put_username(changeset), do: changeset

  # The base, or the base followed by the first number no account took.
  defp free_username(base) do
    taken =
      Dockd.Repo.all(
        from u in __MODULE__, where: like(u.username, ^"#{base}%"), select: u.username
      )
      |> MapSet.new(&String.downcase/1)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  @doc "Changeset for replacing the password."
  def password_changeset(user, attrs),
    do: user |> cast(attrs, [:password]) |> validate_password([])

  # `cast/3` turns an empty string into `nil` before this runs.
  defp trim(nil), do: nil
  defp trim(string), do: String.trim(string)

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> update_change(:email, &trim/1)
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
    |> validate_length(:password, min: 8, max: 72, message: "Mínimo de 8 caracteres")
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
