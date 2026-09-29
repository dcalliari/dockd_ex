defmodule DockdWeb.SettingsLiveTest do
  use DockdWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dockd.AccountsFixtures

  setup :register_and_log_in_user

  test "shows the account fields and the entry point in the account menu", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#account-settings", "Configurações")

    {:ok, view, html} = live(conn, ~p"/configuracoes")

    assert html =~ "Perfil"
    assert html =~ "Conta"
    assert html =~ "Encerrar"
    assert has_element?(view, "#settings-name-form input[value=#{inspect(user.name)}]")
    assert has_element?(view, "#settings-username-form input[value=#{inspect(user.username)}]")
    assert html =~ user.email
  end

  test "changes the display name on blur, with no save button", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    view
    |> form("#settings-name-form", user: %{name: "Novo Nome"})
    |> render_change()

    assert has_element?(view, "#settings-name-form input[value=\"Novo Nome\"]")
  end

  test "rejects an empty display name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    html =
      view
      |> form("#settings-name-form", user: %{name: ""})
      |> render_change()

    assert html =~ "Informe o nome"
  end

  test "changes the username, which changes the profile address", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    view
    |> form("#settings-username-form", user: %{username: "novousuario"})
    |> render_change()

    assert has_element?(view, "#settings-username-form input[value=\"novousuario\"]")
  end

  test "rejects a username already taken", %{conn: conn} do
    other = user_fixture()

    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    html =
      view
      |> form("#settings-username-form", user: %{username: other.username})
      |> render_change()

    assert html =~ "já existe"
  end

  test "reuses the same Choice as the public profile to set privacy", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    view
    |> form("#settings-visibility", visibility: "friends")
    |> render_change()

    assert Dockd.Accounts.get_user!(user.id).profile_visibility == :friends
  end

  test "opens Trocar e-mail in place and confirms with the current password", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    refute has_element?(view, "#settings-email-form")

    view |> element("#settings-email-edit") |> render_click()
    assert has_element?(view, "#settings-email-form")

    assert {:error, {:redirect, %{to: "/entrar"}}} =
             view
             |> form("#settings-email-form",
               user: %{email: "novo@example.com", current_password: valid_user_password()}
             )
             |> render_submit()
  end

  test "rejects the wrong current password when changing email, in place, no dialog", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    view |> element("#settings-email-edit") |> render_click()

    html =
      view
      |> form("#settings-email-form",
        user: %{email: "novo@example.com", current_password: "senha errada"}
      )
      |> render_submit()

    assert html =~ "Senha atual errada"
  end

  test "Cancelar closes Trocar e-mail without changing anything", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    view |> element("#settings-email-edit") |> render_click()
    view |> element("#settings-email-cancel") |> render_click()

    refute has_element?(view, "#settings-email-form")
    assert Dockd.Accounts.get_user!(user.id).email == user.email
  end

  test "changes the password and ends the session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    assert {:error, {:redirect, %{to: "/entrar"}}} =
             view
             |> form("#settings-password-form", user: %{password: "another valid password"})
             |> render_submit()
  end

  test "Excluir conta confirms in place, no native dialog, before deleting", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/configuracoes")

    refute has_element?(view, "#settings-delete-warning")

    view |> element("#settings-delete-confirm") |> render_click()
    assert has_element?(view, "#settings-delete-warning")

    view |> element("#settings-delete-cancel") |> render_click()
    refute has_element?(view, "#settings-delete-warning")
    assert Dockd.Accounts.get_user!(user.id)

    view |> element("#settings-delete-confirm") |> render_click()

    assert {:error, {:redirect, %{to: "/"}}} =
             view |> element("#settings-delete-submit") |> render_click()

    refute Dockd.Repo.get(Dockd.Accounts.User, user.id)
  end

  test "no native dialog anywhere on the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/configuracoes")

    refute html =~ "confirm("
    refute html =~ "data-confirm"
  end
end
