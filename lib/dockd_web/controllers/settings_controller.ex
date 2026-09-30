defmodule DockdWeb.SettingsController do
  use DockdWeb, :controller

  alias Dockd.Accounts

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email_by_token(token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "E-mail confirmado")
        |> redirect(to: ~p"/entrar")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Link vencido")
        |> redirect(to: ~p"/entrar")
    end
  end

  def export(conn, _params) do
    data = Accounts.export_user_data(conn.assigns.current_scope.user)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="dockd-dados.json"))
    |> send_resp(:ok, Jason.encode!(data))
  end
end
