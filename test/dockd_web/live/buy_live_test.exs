defmodule DockdWeb.BuyLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.{Accounts, Purchasing, Wallet}
  alias Dockd.Library.Shelf

  setup do
    user = Accounts.default_owner()
    today = Date.utc_today()

    upcoming = game_fixture(%{title: "Upcoming Exclusive"})
    release_fixture(upcoming, %{platform: :switch_2, release_date: Date.add(today, 10)})
    {:ok, _} = entry_fixture(user, upcoming, %{purchase_intent: :want})

    next_year = game_fixture(%{title: "Next Year Game"})

    release_fixture(next_year, %{
      platform: :switch_2,
      release_date: Date.new!(today.year + 1, 1, 1),
      release_date_precision: :year
    })

    {:ok, _} = entry_fixture(user, next_year, %{purchase_intent: :want})

    available = game_fixture(%{title: "Available Now"})

    available_release =
      release_fixture(available, %{platform: :switch, release_date: Date.add(today, -100)})

    {:ok, _} = entry_fixture(user, available, %{purchase_intent: :want})

    undated = game_fixture(%{title: "Undated Wish"})
    release_fixture(undated, %{platform: :switch, release_date: nil})
    {:ok, _} = entry_fixture(user, undated, %{purchase_intent: :want})

    owned = game_fixture(%{title: "Owned Already"})

    owned_release =
      release_fixture(owned, %{platform: :switch, release_date: Date.add(today, -300)})

    {:ok, _} = purchase_fixture(user, owned_release)

    %{
      user: user,
      upcoming: upcoming,
      next_year: next_year,
      available: available,
      available_release: available_release,
      undated: undated,
      owned: owned
    }
  end

  test "splits the wishlist into upcoming, available and undated", %{conn: conn} = ctx do
    {:ok, view, html} = live(conn, "/comprar")

    assert has_element?(view, "#queue-#{ctx.upcoming.id} .dk-date--soon")
    assert has_element?(view, "#queue-#{ctx.next_year.id} .dk-date--year")
    assert html =~ ~s(class="dk-year-mark")
    assert has_element?(view, "#queue-#{ctx.available.id} button", "Comprei")
    assert has_element?(view, "#queue-#{ctx.undated.id}")
    refute has_element?(view, "#queue-#{ctx.owned.id}")
    refute has_element?(view, "#wallet-line")
  end

  test "shows the eShop balance when there is one", %{conn: conn} = ctx do
    {:ok, _} = balance_fixture(ctx.user, %{amount_cents: 4000})
    {:ok, view, _html} = live(conn, "/comprar")
    assert has_element?(view, "#wallet-line", "R$ 40,00")
  end

  test "reserves money for an upcoming release inline", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/comprar")

    view |> element("#queue-#{ctx.upcoming.id} button", "Reservar") |> render_click()
    view |> form("#reserve-form-#{ctx.upcoming.id}", %{"amount" => "349,90"}) |> render_submit()

    assert [%{amount_cents: 34_990}] = Wallet.list_reservations(ctx.user)
    assert has_element?(view, "#queue-#{ctx.upcoming.id}", "Reservado")
    assert has_element?(view, "#wallet-line", "R$ 349,90")
  end

  test "Comprei takes the game out of the queue", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/comprar")

    view |> element("#queue-#{ctx.available.id} button", "Comprei") |> render_click()
    view |> form("#buy-form-#{ctx.available.id}", %{"price" => "99,90"}) |> render_submit()

    refute has_element?(view, "#queue-#{ctx.available.id}")
    assert Shelf.item(ctx.user, ctx.available).status == :backlog
    assert [%{price_cents: 9_990}] = Purchasing.list_purchases(ctx.user, ctx.available_release.id)
  end
end
