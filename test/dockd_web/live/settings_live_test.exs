defmodule DockdWeb.SettingsLiveTest do
  use DockdWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dockd.AccountsFixtures
  import Dockd.DomainFixtures, only: [game_fixture: 1]

  alias Dockd.{Accounts, Social}

  describe "settings" do
    setup :register_and_log_in_user

    test "opens from the account menu and shows the current identity", %{
      conn: conn,
      user: user
    } do
      {:ok, home, _html} = live(conn, ~p"/")
      assert has_element?(home, "#account-settings[href='/configuracoes']", "Configurações")

      {:ok, view, html} = live(conn, ~p"/configuracoes")

      assert has_element?(
               view,
               "#settings-profile-link[href='/u/#{user.username}']",
               "Ver perfil"
             )

      assert has_element?(view, "#settings-profile-form input[value=#{inspect(user.name)}]")

      assert has_element?(
               view,
               "#settings-profile-form input[value=#{inspect(user.username)}]"
             )

      assert html =~ user.email
    end

    test "updates the public identity on submit, with a saved notice", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      view
      |> element("#settings-profile-form")
      |> render_submit(%{"user" => %{"name" => "Calliari", "username" => "calliari"}})

      assert has_element?(view, "#settings-profile-notice", "Perfil atualizado")
      updated = Accounts.get_user!(user.id)
      assert updated.name == "Calliari"
      assert updated.username == "calliari"
    end

    test "saves the bio, place and link, and clears them when emptied", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      view
      |> element("#settings-profile-form")
      |> render_submit(%{
        "user" => %{
          "name" => user.name,
          "username" => user.username,
          "bio" => "Zerando um jogo por vez",
          "location" => "Belém",
          "link" => "calliari.dev"
        }
      })

      updated = Accounts.get_user!(user.id)
      assert updated.bio == "Zerando um jogo por vez"
      assert updated.location == "Belém"
      assert updated.link == "https://calliari.dev"

      view
      |> element("#settings-profile-form")
      |> render_submit(%{
        "user" => %{"name" => user.name, "username" => user.username, "bio" => "  ", "link" => ""}
      })

      assert Accounts.get_user!(user.id).bio == nil
      assert Accounts.get_user!(user.id).link == nil
    end

    test "rejects a link that is not a web address", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      view
      |> element("#settings-profile-form")
      |> render_submit(%{
        "user" => %{
          "name" => user.name,
          "username" => user.username,
          "link" => "javascript:alert(1)"
        }
      })

      assert has_element?(view, "#settings-profile-form .dk-field__error", "Link inválido")
      assert Accounts.get_user!(user.id).link == nil
    end

    test "shows validation beside the profile field and updates privacy", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      view
      |> element("#settings-profile-form")
      |> render_change(%{"user" => %{"name" => user.name, "username" => "?"}})

      assert has_element?(view, "#settings-profile-form .dk-field__error", "Use letras e números")

      view
      |> element("#settings-visibility")
      |> render_change(%{visibility: "friends"})

      assert Accounts.get_user!(user.id).profile_visibility == :friends
    end

    test "rejects an empty display name", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      html =
        view
        |> element("#settings-profile-form")
        |> render_change(%{"user" => %{"name" => "", "username" => user.username}})

      assert html =~ "Informe este campo"
    end

    test "rejects a username already taken", %{conn: conn, user: user} do
      other = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      html =
        view
        |> element("#settings-profile-form")
        |> render_submit(%{"user" => %{"name" => user.name, "username" => other.username}})

      assert html =~ "já existe"
    end

    test "sends email confirmation without changing the email first", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")
      view |> element("#settings-edit-email") |> render_click()

      view
      |> element("#settings-email-form")
      |> render_submit(%{"email" => %{"email" => "novo@example.com"}})

      assert has_element?(view, "#settings-email-notice", "Confirmação enviada")
      assert Accounts.get_user!(user.id).email == user.email
    end

    test "Cancelar closes Trocar e-mail without changing anything", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      view |> element("#settings-edit-email") |> render_click()
      assert has_element?(view, "#settings-email-form")

      view |> element("#settings-email-form button", "Cancelar") |> render_click()

      refute has_element?(view, "#settings-email-form")
      assert Accounts.get_user!(user.id).email == user.email
    end

    test "requires the current password and ends other sessions", %{conn: conn, user: user} do
      other = Accounts.generate_user_session_token(user)
      {:ok, view, _html} = live(conn, ~p"/configuracoes")
      view |> element("#settings-edit-password") |> render_click()

      view
      |> element("#settings-password-form")
      |> render_submit(%{
        "password" => %{
          "current_password" => "incorreta",
          "new_password" => "uma senha bem longa",
          "confirmation" => "uma senha bem longa"
        }
      })

      assert has_element?(
               view,
               "#settings-password-form .dk-field__error",
               "Senha atual incorreta"
             )

      view |> element("#settings-end-sessions") |> render_click()
      assert has_element?(view, "#settings-session-notice", "Outras sessões encerradas")
      refute Accounts.get_user_by_session_token(other)
    end

    test "changes the password with the current one, and ends other sessions right away", %{
      conn: conn,
      user: user
    } do
      other = Accounts.generate_user_session_token(user)
      {:ok, view, _html} = live(conn, ~p"/configuracoes")
      view |> element("#settings-edit-password") |> render_click()

      view
      |> element("#settings-password-form")
      |> render_submit(%{
        "password" => %{
          "current_password" => valid_user_password(),
          "new_password" => "uma senha bem longa",
          "confirmation" => "uma senha bem longa"
        }
      })

      assert has_element?(view, "#settings-password-notice", "Senha atualizada")
      refute Accounts.get_user_by_session_token(other)
      assert Accounts.get_user_by_email_and_password(user.email, "uma senha bem longa")
    end

    test "exports data and confirms deletion inside the app", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      assert has_element?(
               view,
               "#settings-export[href='/configuracoes/exportar']",
               "Exportar dados"
             )

      view |> element("#settings-delete") |> render_click()
      assert has_element?(view, "#settings-delete-modal[role='presentation']")

      view
      |> element("#settings-delete-form")
      |> render_submit(%{"delete" => %{"confirmation" => "apagar"}})

      assert has_element?(
               view,
               "#settings-delete-form .dk-field__error",
               "Digite EXCLUIR para continuar"
             )
    end

    test "excludes the account once EXCLUIR is typed, ending the session", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      view |> element("#settings-delete") |> render_click()

      view
      |> element("#settings-delete-form")
      |> render_submit(%{"delete" => %{"confirmation" => "EXCLUIR"}})

      assert_redirect(view, ~p"/")
      refute Dockd.Repo.get(Dockd.Accounts.User, user.id)
    end

    test "no native dialog anywhere on the page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/configuracoes")

      refute html =~ "confirm("
      refute html =~ "data-confirm"
    end
  end

  describe "favorites" do
    setup :register_and_log_in_user

    test "fills a position from the search modal, empties it with the X and keeps four at most",
         %{conn: conn, user: user} do
      hollow = game_fixture(%{title: "Hollow Knight"})
      zelda = game_fixture(%{title: "Zelda Echoes"})
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      assert has_element?(view, "#favorite-add-1")
      assert has_element?(view, "#favorite-add-4")
      refute has_element?(view, "#favorite-picker")
      assert has_element?(view, "#settings-sections a[href='#settings-favorites']", "Favoritos")

      view |> element("#favorite-add-1") |> render_click()
      assert has_element?(view, "#favorite-picker[role=presentation] [role=dialog]")
      view |> form("#favorite-search-form", %{q: "hollow"}) |> render_change()
      view |> element("#favorite-choose-#{hollow.id}") |> render_click()

      refute has_element?(view, "#favorite-picker")
      assert has_element?(view, "#favorite-#{hollow.id}[data-position='1']")
      refute has_element?(view, "#favorite-add-1")

      # a favorite already placed never shows up as a result
      view |> element("#favorite-add-2") |> render_click()
      view |> form("#favorite-search-form", %{q: "hollow"}) |> render_change()
      refute has_element?(view, "#favorite-result-#{hollow.id}")
      view |> form("#favorite-search-form", %{q: "zelda"}) |> render_change()
      view |> element("#favorite-choose-#{zelda.id}") |> render_click()
      assert has_element?(view, "#favorite-#{zelda.id}[data-position='2']")

      view |> element("#favorite-remove-1") |> render_click()
      assert has_element?(view, "#favorite-add-1")
      refute has_element?(view, "#favorite-#{hollow.id}")
      assert has_element?(view, "#favorite-#{zelda.id}[data-position='2']")
    end

    test "the picker closes with Fechar and Escape, choosing nothing", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      view |> element("#favorite-add-3") |> render_click()
      view |> element("#favorite-picker-close") |> render_click()
      refute has_element?(view, "#favorite-picker")

      view |> element("#favorite-add-3") |> render_click()
      render_keydown(view, "close_picker", %{"key" => "Escape"})
      refute has_element?(view, "#favorite-picker")
      assert Social.favorites(user) == []
    end

    test "dragging a favorite onto a position moves it and swaps with the one there",
         %{conn: conn, user: user} do
      a = game_fixture(%{title: "Fav A"})
      b = game_fixture(%{title: "Fav B"})
      :ok = Social.put_favorite(user, a, 1)
      :ok = Social.put_favorite(user, b, 2)
      {:ok, view, _html} = live(conn, ~p"/configuracoes")

      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "2"})
      assert has_element?(view, "#favorite-#{a.id}[data-position='2']")
      assert has_element?(view, "#favorite-#{b.id}[data-position='1']")

      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "4"})
      assert has_element?(view, "#favorite-#{a.id}[data-position='4']")
      assert has_element?(view, "#favorite-add-2")

      # an out-of-range or unreadable position changes nothing
      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "5"})
      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "x"})
      assert Enum.map(Social.favorite_slots(user), &(&1 && &1.position)) == [1, nil, nil, 4]
    end
  end
end
