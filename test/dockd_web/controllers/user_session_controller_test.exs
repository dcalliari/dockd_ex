defmodule DockdWeb.UserSessionControllerTest do
  use DockdWeb.ConnCase, async: true

  import Dockd.AccountsFixtures

  alias Dockd.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "POST /entrar with password" do
    test "signs in, remembers the device and opens the library", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/entrar", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_dockd_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"

      conn = get(recycle(conn), ~p"/")
      assert html_response(conn, 200) =~ user.email
    end

    test "goes back to where the visitor was headed", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/comprar")
        |> post(~p"/entrar", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/comprar"
    end

    test "a wrong password goes back to Entrar with the error on the field", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, ~p"/entrar", %{
          "user" => %{"email" => user.email, "password" => "senha errada!!"}
        })

      assert redirected_to(conn) == ~p"/entrar"
      assert Phoenix.Flash.get(conn.assigns.flash, :password_error) == "E-mail ou senha errados"
      refute get_session(conn, :user_token)
    end
  end

  describe "POST /entrar with a magic link token" do
    test "signs in and confirms the email", %{conn: conn, user: user} do
      {token, _hashed} = generate_user_magic_link_token(user)
      conn = post(conn, ~p"/entrar", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "a used link goes back to Entrar", %{conn: conn, user: user} do
      {token, _hashed} = generate_user_magic_link_token(user)
      {:ok, _} = Accounts.login_user_by_magic_link(token)

      conn = post(conn, ~p"/entrar", %{"user" => %{"token" => token}})

      assert redirected_to(conn) == ~p"/entrar"
      assert Phoenix.Flash.get(conn.assigns.flash, :link_error) == "Link vencido"
    end
  end

  describe "DELETE /sair" do
    test "signs out and goes to Entrar", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/sair")

      assert redirected_to(conn) == ~p"/entrar"
      refute get_session(conn, :user_token)
    end
  end
end
