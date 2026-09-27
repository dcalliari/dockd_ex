defmodule DockdWeb.BuyLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Library.Shelf
  alias Dockd.Purchasing

  setup :register_and_log_in_user

  setup %{user: user} do
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
    refute has_element?(view, "button", "Reservar")
  end

  test "the line on top shows the month's spending and no estimate without prices",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/comprar")

    assert has_element?(view, "#month-spending", "R$ 10,00")
    refute has_element?(view, "#estimate-digital")
    refute has_element?(view, "#estimate-physical")
  end

  test "the estimate adds each media's prices and says how many games it covers",
       %{conn: conn} = ctx do
    observe(ctx.user, ctx.available_release, :digital, 9_990)
    {:ok, view, _html} = live(conn, "/comprar")

    assert has_element?(view, "#estimate-digital", "R$ 99,90")
    assert has_element?(view, "#estimate-digital", "em 1 de 4")
    refute has_element?(view, "#estimate-physical")
    assert has_element?(view, "#price-#{ctx.available.id}", "R$ 99,90")
  end

  test "Comprei buys in one tap with the price seen, then Desfazer undoes it",
       %{conn: conn} = ctx do
    observe(ctx.user, ctx.available_release, :digital, 9_990)
    {:ok, view, _html} = live(conn, "/comprar")

    view |> element("#buy-#{ctx.available.id}-button") |> render_click()

    assert Shelf.item(ctx.user, ctx.available).status == :backlog

    assert [%{price_cents: 9_990, retailer: "eShop"}] =
             Purchasing.list_purchases(ctx.user, ctx.available_release.id)

    assert has_element?(view, "#buy-#{ctx.available.id} .dk-status--backlog")
    assert has_element?(view, "#buy-#{ctx.available.id}", "pago em")
    refute has_element?(view, "#estimate-digital")

    view |> element("#buy-#{ctx.available.id} button", "Desfazer") |> render_click()

    assert Shelf.item(ctx.user, ctx.available).status == :quero
    assert Purchasing.list_purchases(ctx.user, ctx.available_release.id) == []
    assert has_element?(view, "#buy-#{ctx.available.id}-button")
  end

  test "the paid value opens in place and takes a correction", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/comprar")

    view |> element("#buy-#{ctx.available.id}-button") |> render_click()
    assert has_element?(view, "#buy-#{ctx.available.id}", "Sem valor")

    view |> element("#buy-#{ctx.available.id} button", "Sem valor") |> render_click()
    view |> form("#buy-#{ctx.available.id} form", %{"price" => "abc"}) |> render_submit()
    assert has_element?(view, "#buy-#{ctx.available.id} .dk-field__error", "Use 199,90")

    view |> form("#buy-#{ctx.available.id} form", %{"price" => "89,90"}) |> render_submit()

    assert [%{price_cents: 8_990}] = Purchasing.list_purchases(ctx.user, ctx.available_release.id)
    assert has_element?(view, "#buy-#{ctx.available.id}", "R$ 89,90")
  end

  test "the price opens the manual record under the row", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/comprar")

    view |> element("#price-#{ctx.upcoming.id}") |> render_click()

    view
    |> form("#price-form-#{ctx.upcoming.id}", %{"price" => "349,90", "source" => "Amazon"})
    |> render_submit()

    refute has_element?(view, "#price-form-#{ctx.upcoming.id}")
    assert has_element?(view, "#price-#{ctx.upcoming.id}", "R$ 349,90")
  end

  defp observe(user, release, format, cents) do
    {:ok, _} =
      Purchasing.create_price_observation(user, %{
        release_id: release.id,
        format: format,
        price_cents: cents,
        observed_at: DateTime.utc_now(),
        source: "eShop"
      })
  end
end
