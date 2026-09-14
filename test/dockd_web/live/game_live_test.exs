defmodule DockdWeb.GameLiveTest do
  use DockdWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures
  alias Dockd.{Accounts, Library, Purchasing, Repo}
  alias Dockd.Library.Ownership

  setup do
    game = game_fixture(%{title: "Metroid Prime 4"})
    release = release_fixture(game, %{platform: :switch, physical_available: true})
    release_2 = release_fixture(game, %{platform: :switch_2, digital_available: true})
    %{game: game, release: release, release_2: release_2, user: Accounts.default_owner()}
  end

  test "records an observation and shows stale state", %{
    conn: conn,
    game: game,
    release: release,
    user: user
  } do
    old = DateTime.add(DateTime.utc_now(), -8, :day)

    assert {:ok, _} =
             Purchasing.create_price_observation(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: 19_990,
               observed_at: old,
               source: "eShop"
             })

    {:ok, view, _html} = live(conn, ~p"/jogos/#{game.id}")
    assert has_element?(view, "#observation-form-#{release.id}")

    assert render_submit(element(view, "#observation-form-#{release.id}"), %{
             "observation" => %{
               "format" => "digital",
               "price_cents" => "18990",
               "currency" => "BRL",
               "observed_at" => "2026-09-14T10:00",
               "source" => "eShop"
             }
           })

    assert has_element?(view, "#releases")
    assert render(view) =~ "desatualizado"
  end

  test "purchase records matching ownership", %{
    conn: conn,
    game: game,
    release: release,
    user: user
  } do
    {:ok, view, _} = live(conn, ~p"/jogos/#{game.id}")

    render_submit(element(view, "#purchase-form-#{release.id}"), %{
      "purchase" => %{
        "format" => "physical",
        "price_cents" => "19990",
        "currency" => "BRL",
        "purchased_at" => "2026-09-14T10:00",
        "retailer" => "Nintendo Store"
      }
    })

    assert Repo.exists?(
             from o in Ownership,
               where:
                 o.user_id == ^user.id and o.release_id == ^release.id and
                   o.ownership_type == :physical
           )
  end

  test "veto can be undone", %{conn: conn, game: game, release: release, user: user} do
    {:ok, view, _} = live(conn, ~p"/jogos/#{game.id}")

    render_submit(element(view, "#veto-form-#{release.id}"), %{
      "veto" => %{"reason" => "Prefiro esperar"}
    })

    veto = Library.get_veto_for_release(user, release.id)
    assert veto
    assert veto.reason == "Prefiro esperar"
    assert {:ok, _} = Library.delete_veto(user, veto)
    assert Library.get_veto_for_release(user, release.id) == nil
  end
end
