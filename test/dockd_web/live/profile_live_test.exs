defmodule DockdWeb.ProfileLiveTest do
  use DockdWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures, only: [game_fixture: 1, release_fixture: 2, purchase_fixture: 3]

  alias Dockd.{AccountsFixtures, Library, Social}

  setup do
    ana = AccountsFixtures.user_fixture(%{email: "ana@example.com"})
    playing = game_fixture(%{title: "Hollow Knight", cover_url: "https://c/hk.jpg"})
    wanted = game_fixture(%{title: "Hades II"})
    release = release_fixture(playing, %{})
    release_fixture(wanted, %{})

    {:ok, _} =
      Library.set_status(ana, playing, :jogando,
        ownership: %{release_id: release.id, ownership_type: :physical}
      )

    {:ok, _} = Library.set_status(ana, wanted, :quero)
    {:ok, _} = purchase_fixture(ana, release, %{price_cents: 7990})

    %{ana: ana, playing: playing, wanted: wanted}
  end

  describe "a visitor" do
    test "sees the head, the Estante and the Diário, never a price", %{conn: conn} = ctx do
      {:ok, view, html} = live(conn, ~p"/u/ana")

      assert has_element?(view, "#profile-head h1", "Ana")
      assert has_element?(view, "#profile-head .dk-avatar", "A")
      assert has_element?(view, "#profile-head", "@ana")
      assert has_element?(view, "#profile-games b", "2")
      assert has_element?(view, "#profile-year b", "#{length(Social.diary(ctx.ana))}")
      assert has_element?(view, "#profile-playing-now #profile-now-#{ctx.playing.id}")
      assert has_element?(view, "#profile-stat-quero[href='/u/ana/quero'] b", "1")
      assert has_element?(view, "#profile-stat-jogando[href='/u/ana/jogando'] b", "1")
      assert has_element?(view, "#profile-sidebar")
      assert has_element?(view, "#profile-diary-months .dk-month .dk-status--jogando")
      refute has_element?(view, "#profile-edit")
      refute has_element?(view, "#profile-finished")
      refute html =~ "R$"
      refute html =~ "79,90"

      assert has_element?(
               view,
               "#follow-button[href='#{~p"/entrar?#{%{volta: "/u/ana"}}"}']",
               "Seguir"
             )
    end

    test "shows Quero as a fan of five covers and the count only in the Estante",
         %{conn: conn, ana: ana} do
      for index <- 1..10 do
        {:ok, _} = Library.set_status(ana, game_fixture(%{title: "Wish #{index}"}), :quero)
      end

      {:ok, view, _html} = live(conn, ~p"/u/ana")

      assert has_element?(view, "#profile-stat-quero[href='/u/ana/quero'] b", "11")
      assert has_element?(view, "#profile-wishlist-link[href='/u/ana/quero']", "Ver todos")
      refute has_element?(view, "#profile-wishlist-head span")

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#profile-wishlist-fan .dk-poster")
             |> Enum.count() == 5

      refute has_element?(view, "#profile-quero-strip")
    end

    test "shows the bio, place and link the owner wrote, with the link as its host",
         %{conn: conn, ana: ana} do
      {:ok, _} =
        Dockd.Accounts.update_user_profile(ana, %{
          bio: "Zerando um jogo por vez",
          location: "Belém, Brasil",
          link: "www.ana.dev/jogos"
        })

      {:ok, view, _html} = live(conn, ~p"/u/ana")

      assert has_element?(view, "#profile-bio", "Zerando um jogo por vez")
      assert has_element?(view, "#profile-location", "Belém, Brasil")
      assert has_element?(view, "#profile-link[href='https://www.ana.dev/jogos']", "ana.dev")
    end

    test "charts the games finished in the year only once there is one",
         %{conn: conn, ana: ana} do
      {:ok, view, _html} = live(conn, ~p"/u/ana")
      refute has_element?(view, "#profile-finished")

      {:ok, _} =
        Library.set_status(ana, game_fixture(%{title: "Celeste"}), :zerado, owned_elsewhere: true)

      {:ok, view, _html} = live(conn, ~p"/u/ana")

      assert has_element?(view, "#profile-finished-head", "Zerados em #{Date.utc_today().year}")
      assert has_element?(view, "#profile-finished .dk-profile-histo i.is-on")
    end

    test "sees only the name when the profile is for friends", %{conn: conn, ana: ana} do
      {:ok, _} = Social.set_visibility(ana, :friends)
      {:ok, view, _html} = live(conn, ~p"/u/ana")

      assert has_element?(view, "#profile-head h1", "Ana")
      assert has_element?(view, "#profile-closed", "Perfil só para amigos.")
      assert has_element?(view, "#profile-numbers #profile-followers", "Seguidores")
      refute has_element?(view, "#profile-games")
      refute has_element?(view, "#profile-year")
      refute has_element?(view, "#profile-bio")
      refute has_element?(view, "#profile-jogando")
      refute has_element?(view, "a#profile-followers")

      {:ok, view, _html} = live(conn, ~p"/u/ana/diario")
      assert has_element?(view, "#profile-closed")
      refute has_element?(view, "#diary")
    end

    test "opens the Diário from Recente, one row per change with the date on the first",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/u/ana")
      assert has_element?(view, "#profile-diary-link[href='/u/ana/diario']", "Ver diário")
      assert has_element?(view, "#profile-diary-months .dk-month .dk-date--month")

      {:ok, view, html} = live(conn, ~p"/u/ana/diario")
      assert has_element?(view, "#profile-back", "Ana")
      assert has_element?(view, "#profile-diary", "Diário")
      assert has_element?(view, "#diary .dk-entry[data-status='jogando']", "Hollow Knight")
      assert has_element?(view, "#diary .dk-entry[data-status='quero']", "Hades II")
      assert has_element?(view, "#diary .dk-entry--first .dk-date")
      refute has_element?(view, "#diary .dk-date--soon")

      assert html |> LazyHTML.from_document() |> LazyHTML.query("#diary .dk-date") |> Enum.count() ==
               1

      refute html =~ "R$"
    end

    test "a full day shows ten rows and Mais N opens the rest in place", %{conn: conn, ana: ana} do
      for index <- 1..12 do
        {:ok, _} = Library.set_status(ana, game_fixture(%{title: "Wish #{index}"}), :quero)
      end

      {:ok, view, _html} = live(conn, ~p"/u/ana/diario")
      today = Date.to_iso8601(Date.utc_today())
      assert view |> element("#diary-more-#{today}") |> render() =~ "Mais 4 neste dia"

      view |> element("#diary-more-#{today}") |> render_click()
      refute has_element?(view, "#diary-more-#{today}")
      assert has_element?(view, "#diary .dk-entry", "Wish 1")
    end

    test "finds no profile for an unknown name", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/u/ninguem") end
    end
  end

  describe "an account" do
    setup :register_and_log_in_user

    test "follows, sees Seguindo, and friends get the label", %{conn: conn, user: user, ana: ana} do
      {:ok, view, _html} = live(conn, ~p"/u/ana")

      view |> element("#follow-button", "Seguir") |> render_click()
      assert has_element?(view, "#follow-button.dk-follow", "Seguindo")
      refute has_element?(view, "#profile-head .dk-friend")

      :ok = Social.follow(ana, user)
      {:ok, view, _html} = live(conn, ~p"/u/ana")
      assert has_element?(view, "#profile-head .dk-friend", "Amigo")
      assert has_element?(view, "#follow-button", "Seguindo")

      view |> element("#follow-button") |> render_click()
      assert has_element?(view, "#follow-button", "Seguir de volta")
      assert Social.relation(user, ana) == :followed_by
    end

    test "opens a friends-only profile to a friend", %{conn: conn, user: user, ana: ana} do
      {:ok, _} = Social.set_visibility(ana, :friends)
      :ok = Social.follow(user, ana)
      {:ok, view, _html} = live(conn, ~p"/u/ana")
      assert has_element?(view, "#profile-closed")

      :ok = Social.follow(ana, user)
      {:ok, view, _html} = live(conn, ~p"/u/ana")
      refute has_element?(view, "#profile-closed")
      assert has_element?(view, "#profile-playing")
    end

    test "offers Editar perfil in place of Seguir, with no visibility control", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/u/#{user.username}")

      refute has_element?(view, "#follow-button")
      assert has_element?(view, "#profile-edit[href='/configuracoes']", "Editar perfil")
      refute has_element?(view, "#profile-visibility")
    end

    test "carries its own status on the covers, as in Descobrir",
         %{conn: conn, user: user} = ctx do
      {:ok, _} = Library.set_status(user, ctx.playing, :zerado, owned_elsewhere: true)
      {:ok, view, _html} = live(conn, ~p"/u/ana")

      card = "#profile-now-#{ctx.playing.id}"
      assert has_element?(view, "#{card}[data-status='zerado']")
    end

    test "fills a position from the search modal, empties it with the X and keeps four at most",
         %{conn: conn, user: user} = ctx do
      zelda = game_fixture(%{title: "Zelda Echoes"})
      {:ok, view, _html} = live(conn, ~p"/u/#{user.username}")

      assert has_element?(view, "#favorite-add-1")
      assert has_element?(view, "#favorite-add-4")
      refute has_element?(view, "#favorite-picker")
      refute has_element?(view, "#profile-edit-favorites")

      view |> element("#favorite-add-1") |> render_click()
      assert has_element?(view, "#favorite-picker[role=presentation] [role=dialog]")
      view |> form("#favorite-search-form", %{q: "hollow"}) |> render_change()
      view |> element("#favorite-choose-#{ctx.playing.id}") |> render_click()

      refute has_element?(view, "#favorite-picker")
      assert has_element?(view, "#profile-favorite-#{ctx.playing.id}[data-position='1']")
      refute has_element?(view, "#favorite-add-1")

      # a favorite already placed never shows up as a result
      view |> element("#favorite-add-2") |> render_click()
      view |> form("#favorite-search-form", %{q: "hollow"}) |> render_change()
      refute has_element?(view, "#favorite-result-#{ctx.playing.id}")
      view |> form("#favorite-search-form", %{q: "zelda"}) |> render_change()
      view |> element("#favorite-choose-#{zelda.id}") |> render_click()
      assert has_element?(view, "#profile-favorite-#{zelda.id}[data-position='2']")

      view |> element("#favorite-remove-1") |> render_click()
      assert has_element?(view, "#favorite-add-1")
      refute has_element?(view, "#profile-favorite-#{ctx.playing.id}")
      assert has_element?(view, "#profile-favorite-#{zelda.id}[data-position='2']")
    end

    test "the picker closes with Fechar and Escape, choosing nothing", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/u/#{user.username}")

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
      {:ok, view, _html} = live(conn, ~p"/u/#{user.username}")

      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "2"})
      assert has_element?(view, "#profile-favorite-#{a.id}[data-position='2']")
      assert has_element?(view, "#profile-favorite-#{b.id}[data-position='1']")

      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "4"})
      assert has_element?(view, "#profile-favorite-#{a.id}[data-position='4']")
      assert has_element?(view, "#favorite-add-2")

      # an out-of-range or unreadable position changes nothing
      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "5"})
      render_click(view, "place_favorite", %{"game_id" => a.id, "position" => "x"})
      assert Enum.map(Social.favorite_slots(user), &(&1 && &1.position)) == [1, nil, nil, 4]
    end

    test "a visitor sees the favorites with no X, no + and no hook", %{conn: conn, ana: ana} do
      :ok = Social.put_favorite(ana, game_fixture(%{title: "Fav A"}), 1)
      {:ok, view, html} = live(conn, ~p"/u/ana")

      assert has_element?(view, "#profile-favorites-grid .dk-card")
      refute html =~ "dk-fav-remove"
      refute html =~ "dk-fav-add"
      refute html =~ "FavoriteSlots"
    end

    test "only the owner changes favorites", %{conn: conn, ana: ana} do
      {:ok, view, _html} = live(conn, ~p"/u/ana")
      render_click(view, "open_picker", %{"position" => "1"})
      refute has_element?(view, "#favorite-picker")
      render_click(view, "clear_favorite", %{"position" => "1"})
      assert Social.favorites(ana) == []
    end

    test "lists followers with the friend label and each follow button",
         %{conn: conn, user: user, ana: ana} do
      bia = AccountsFixtures.user_fixture(%{email: "bia@example.com"})
      :ok = Social.follow(user, ana)
      :ok = Social.follow(ana, user)
      :ok = Social.follow(bia, ana)

      {:ok, _} =
        Library.set_status(bia, game_fixture(%{title: "Elden Ring"}), :jogando,
          owned_elsewhere: true
        )

      {:ok, view, _html} = live(conn, ~p"/u/ana/seguidores")

      assert has_element?(view, "#profile-back", "Ana")
      assert has_element?(view, "#person-#{user.username}")
      assert has_element?(view, "#person-bia .dk-row__meta", "Jogando Elden Ring")
      refute has_element?(view, "#person-bia .dk-friend")
      assert has_element?(view, "#follow-bia", "Seguir")

      view |> element("#follow-bia") |> render_click()
      assert has_element?(view, "#follow-bia", "Seguindo")

      refute has_element?(view, "#person-#{user.username} .dk-friend")
      refute has_element?(view, "#follow-#{user.username}")

      {:ok, view, _html} = live(conn, ~p"/u/#{user.username}/seguidores")
      assert has_element?(view, "#person-ana .dk-friend", "Amigo")
      assert has_element?(view, "#follow-ana", "Seguindo")
    end

    test "reaches its profile from the account menu", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#account-profile[href='/u/#{user.username}']", "Perfil")
    end

    test "sees what friends play on Início, and only friends", %{conn: conn, user: user} = ctx do
      bia = AccountsFixtures.user_fixture(%{email: "bia@example.com"})
      caio = AccountsFixtures.user_fixture(%{email: "caio@example.com"})
      elden = game_fixture(%{title: "Elden Ring"})
      {:ok, _} = Library.set_status(bia, elden, :jogando, owned_elsewhere: true)
      {:ok, _} = Library.set_status(caio, ctx.wanted, :jogando, owned_elsewhere: true)
      :ok = Social.follow(user, bia)
      :ok = Social.follow(bia, user)
      :ok = Social.follow(user, caio)

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#home-friends", "Amigos jogando")
      assert has_element?(view, "#home-friends-#{elden.id} .dk-card__meta", "Bia")
      assert has_element?(view, "#home-friends-#{elden.id} .dk-status--add")
      refute has_element?(view, "#home-friends-#{ctx.wanted.id}")
    end

    test "Início has no friends strip without friends playing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#home-friends")
    end
  end
end
