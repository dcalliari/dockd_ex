defmodule DockdWeb.UserSessionController do
  use DockdWeb, :controller

  alias Dockd.Accounts
  alias DockdWeb.UserAuth

  # The Entrar screen checks credentials before it posts here, so a failure below only
  # happens on a race or a forged request: it goes back to Entrar with the error in place.
  def create(conn, %{"user" => %{"token" => token}}) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)
        UserAuth.log_in_user(conn, user)

      _ ->
        conn
        |> put_flash(:link_error, "Link vencido")
        |> redirect(to: ~p"/entrar")
    end
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      UserAuth.log_in_user(conn, user)
    else
      conn
      |> put_flash(:password_error, "E-mail ou senha errados")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/entrar")
    end
  end

  def delete(conn, _params), do: UserAuth.log_out_user(conn)
end
