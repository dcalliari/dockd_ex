defmodule Dockd.AccountsTest do
  use Dockd.DataCase

  import Dockd.AccountsFixtures

  alias Dockd.Accounts
  alias Dockd.Accounts.{User, UserToken}
  alias Dockd.Repo

  describe "register_user/1" do
    test "creates an account with a hashed password and a name from the email" do
      {:ok, user} =
        Accounts.register_user(%{email: "daniel@dpe.dev", password: valid_user_password()})

      assert user.name == "Daniel"
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
      assert is_nil(user.confirmed_at)
    end

    test "rejects a bad email, a short password and a taken email, in Portuguese" do
      {:error, changeset} = Accounts.register_user(%{email: "sem arroba", password: "curta"})

      assert %{email: ["E-mail inválido"], password: ["Mínimo de 12 caracteres"]} =
               errors_on(changeset)

      user = user_fixture()

      {:error, changeset} =
        Accounts.register_user(%{email: user.email, password: valid_user_password()})

      assert %{email: ["E-mail já tem conta"]} = errors_on(changeset)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns the user only with the right password" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())

      refute Accounts.get_user_by_email_and_password(user.email, "senha errada!!")
      refute Accounts.get_user_by_email_and_password("ninguem@example.com", valid_user_password())
    end
  end

  describe "claim_owner/2" do
    test "gives the library that predates accounts an email and a password, keeping its id" do
      owner = Repo.insert!(%User{name: "Owner"})
      _later = user_fixture()

      {:ok, claimed} = Accounts.claim_owner("dono@example.com", valid_user_password())

      assert claimed.id == owner.id
      assert claimed.email == "dono@example.com"

      assert Accounts.get_user_by_email_and_password("dono@example.com", valid_user_password()).id ==
               owner.id

      assert {:error, :already_claimed} =
               Accounts.claim_owner("outro@example.com", valid_user_password())
    end

    test "does nothing without users" do
      assert {:error, :no_owner} = Accounts.claim_owner("dono@example.com", valid_user_password())
    end
  end

  describe "reset_password/2" do
    test "replaces the password and ends every session" do
      user = user_fixture()
      session = Accounts.generate_user_session_token(user)

      {:ok, {_user, [_expired]}} = Accounts.reset_password(user.email, "outra senha longa")

      assert Accounts.get_user_by_email_and_password(user.email, "outra senha longa")
      refute Accounts.get_user_by_session_token(session)

      assert {:error, :not_found} =
               Accounts.reset_password("ninguem@example.com", "outra senha longa")
    end
  end

  describe "session tokens" do
    test "a session token finds its user until it is deleted" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {%User{id: id}, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert id == user.id

      Accounts.delete_user_session_token(token)
      refute Accounts.get_user_by_session_token(token)
    end

    test "a session token expires after 14 days" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      offset_user_token(token, -15, :day)
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "magic link" do
    test "is not sent while links are disabled" do
      Application.put_env(:dockd, :magic_link, false)
      on_exit(fn -> Application.put_env(:dockd, :magic_link, true) end)

      user = user_fixture()

      assert {:error, :magic_link_disabled} =
               Accounts.deliver_login_instructions(user, &"/entrar/#{&1}")

      refute Repo.get_by(UserToken, user_id: user.id, context: "login")
    end

    test "the first link confirms the email and discards a password set before it" do
      user = user_fixture()
      session = Accounts.generate_user_session_token(user)
      token = extract_user_token(&Accounts.deliver_login_instructions(user, &1))

      assert Accounts.get_user_by_magic_link_token(token).id == user.id
      {:ok, {confirmed, expired}} = Accounts.login_user_by_magic_link(token)

      assert confirmed.confirmed_at
      assert is_nil(confirmed.hashed_password)
      assert length(expired) == 2
      refute Accounts.get_user_by_session_token(session)
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "a confirmed user keeps the password and the link works once" do
      user = user_fixture()
      {first, _} = generate_user_magic_link_token(user)
      {:ok, _} = Accounts.login_user_by_magic_link(first)
      Accounts.reset_password(user.email, valid_user_password())

      {token, _} = generate_user_magic_link_token(user)
      assert {:ok, {%User{}, []}} = Accounts.login_user_by_magic_link(token)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "an old or malformed link is refused" do
      user = user_fixture()
      {token, hashed} = generate_user_magic_link_token(user)
      offset_user_token(hashed, -16, :minute)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(token)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link("não é token")
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "API tokens" do
    test "a new token replaces the previous one" do
      user = user_fixture()
      {:ok, first} = Accounts.create_api_token(user)
      assert Accounts.get_user_by_api_token(first).id == user.id

      {:ok, second} = Accounts.create_api_token(user)
      refute Accounts.get_user_by_api_token(first)
      assert Accounts.get_user_by_api_token(second).id == user.id
      refute Accounts.get_user_by_api_token("inválido")
    end
  end
end
