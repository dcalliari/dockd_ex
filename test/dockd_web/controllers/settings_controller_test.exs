defmodule DockdWeb.SettingsControllerTest do
  use DockdWeb.ConnCase, async: true

  import Dockd.AccountsFixtures

  alias Dockd.Accounts

  test "GET /configuracoes/email/:token confirms a requested email", %{conn: conn} do
    user = user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_email_change_instructions(user, %{email: "novo@example.com"}, url)
      end)

    conn = get(conn, ~p"/configuracoes/email/#{token}")

    assert redirected_to(conn) == ~p"/entrar"
    assert Accounts.get_user!(user.id).email == "novo@example.com"
  end

  test "GET /configuracoes/exportar downloads the signed-in account data", %{conn: conn} do
    user = user_fixture()

    conn = conn |> log_in_user(user) |> get(~p"/configuracoes/exportar")

    assert response_content_type(conn, :json)

    assert get_resp_header(conn, "content-disposition") == [
             "attachment; filename=\"dockd-dados.json\""
           ]

    assert %{"profile" => %{"email" => email}} = Jason.decode!(conn.resp_body)
    assert email == user.email
  end
end
