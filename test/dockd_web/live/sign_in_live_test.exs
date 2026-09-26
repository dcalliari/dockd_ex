defmodule DockdWeb.SignInLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.AccountsFixtures
  import Swoosh.TestAssertions

  alias Dockd.Accounts

  describe "signed out" do
    test "Comprar is the only screen that goes to Entrar", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/entrar"}}} = live(conn, "/comprar")
      assert {:ok, _, _} = live(conn, "/")
      assert {:ok, _, _} = live(conn, "/descobrir")
    end

    test "Entrar shows the visitor bar and the shelf of catalog covers", %{conn: conn} do
      game =
        Dockd.DomainFixtures.game_fixture(%{title: "Capa Real", cover_url: "https://c/1.jpg"})

      Dockd.DomainFixtures.release_fixture(game, %{release_date: Date.add(Date.utc_today(), -30)})
      {:ok, view, _html} = live(conn, ~p"/entrar")

      assert has_element?(view, ".dk-nav .dk-wordmark")
      assert has_element?(view, ".dk-nav__guest a[aria-current=page]", "Entrar")
      refute has_element?(view, "#account-menu")
      refute has_element?(view, ".dk-bottomnav")
      assert has_element?(view, "#entrar-shelf[aria-hidden=true] img[src='#{game.cover_url}']")
      assert has_element?(view, "#entrar-shelf .dk-poster__status")
    end

    test "Criar conta has its own address in the bar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/criar-conta")

      assert has_element?(view, ".dk-nav__guest a[aria-current=page]", "Criar conta")
      assert has_element?(view, "#entrar-submit", "Criar conta")
    end

    test "the API needs a token", %{conn: conn} do
      assert conn |> get("/api/v1/entries") |> json_response(401)
      assert conn |> get("/api/openapi") |> json_response(200)
    end
  end

  describe "password" do
    test "a right password posts to the session", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/entrar")

      form =
        form(view, "#entrar-form", user: %{email: user.email, password: valid_user_password()})

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "a wrong password shows under the field, in place", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/entrar")

      view
      |> form("#entrar-form", user: %{email: user.email, password: "senha errada!!"})
      |> render_submit()

      assert has_element?(view, ".dk-field.is-error .dk-field__error", "E-mail ou senha errados")
      assert has_element?(view, "#entrar-submit", "Entrar")
    end

    test "a signed-in visitor goes to the library", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/entrar")
    end
  end

  describe "Criar conta" do
    test "switches in place and creates the account", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/entrar")

      view |> element("#entrar-register") |> render_click()
      assert_patch(view, ~p"/criar-conta")
      assert has_element?(view, "#entrar-submit", "Criar conta")
      assert has_element?(view, "#entrar-password", "Já tenho conta")

      form =
        form(view, "#entrar-form",
          user: %{email: "nova@example.com", password: "uma senha longa"}
        )

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_email("nova@example.com").name == "Nova"
    end

    test "shows each field's error in Portuguese", %{conn: conn} do
      taken = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/entrar")
      view |> element("#entrar-register") |> render_click()

      view
      |> form("#entrar-form", user: %{email: taken.email, password: "curta"})
      |> render_submit()

      assert has_element?(view, ".dk-field__error", "E-mail já tem conta")
      assert has_element?(view, ".dk-field__error", "Mínimo de 12 caracteres")
    end
  end

  describe "Entrar por link" do
    test "sends a link and the button says so, in place", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/entrar")

      view |> element("#entrar-link") |> render_click()
      refute has_element?(view, "input[type=password]")
      assert has_element?(view, "#entrar-submit", "Receber link")

      view |> form("#entrar-form", user: %{email: user.email}) |> render_submit()

      assert has_element?(view, "#entrar-submit[disabled]", "Link enviado")
      assert_email_sent(to: [{"", user.email}], subject: "Entrar no Dockd")
    end

    test "an unknown email gets the same answer and no email", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/entrar")
      view |> element("#entrar-link") |> render_click()
      view |> form("#entrar-form", user: %{email: "ninguem@example.com"}) |> render_submit()

      assert has_element?(view, "#entrar-submit[disabled]", "Link enviado")
      assert_no_email_sent()
    end

    test "is not offered while SMTP is not configured", %{conn: conn} do
      Application.put_env(:dockd, :magic_link, false)
      on_exit(fn -> Application.put_env(:dockd, :magic_link, true) end)

      {:ok, view, _html} = live(conn, ~p"/entrar")

      assert has_element?(view, "#entrar-register", "Criar conta")
      refute has_element?(view, "#entrar-link")
    end

    test "the link opens a page whose button signs in", %{conn: conn} do
      user = user_fixture()
      {token, _hashed} = generate_user_magic_link_token(user)

      {:ok, view, _html} = live(conn, ~p"/entrar/#{token}")
      assert has_element?(view, "input[readonly][value='#{user.email}']")

      form = form(view, "#magic-link-form")
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "a stale link goes back to Entrar with the error on the email", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/entrar", flash: flash}}} =
               live(conn, ~p"/entrar/token-que-nao-existe")

      assert flash["link_error"] == "Link vencido"
    end
  end

  describe "account menu" do
    setup :register_and_log_in_user

    test "shows the name and email, and copies a new API token", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#account-menu summary", user.name)
      assert has_element?(view, "#account-menu .dk-account__who", user.email)
      assert has_element?(view, "#account-sign-out[href='/sair']")

      view |> element("#account-api-token") |> render_click()
      assert_push_event(view, "copy_api_token", %{token: token})
      assert Accounts.get_user_by_api_token(token).id == user.id
    end

    test "each account sees only its own library", %{conn: conn} do
      other = user_fixture()
      game = Dockd.DomainFixtures.game_fixture(%{title: "Only Mine"})
      {:ok, _} = Dockd.DomainFixtures.entry_fixture(other, game, %{purchase_intent: :want})

      {:ok, view, _html} = live(conn, ~p"/")
      refute render(view) =~ "Only Mine"
    end
  end
end
