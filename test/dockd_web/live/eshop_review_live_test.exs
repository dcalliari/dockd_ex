defmodule DockdWeb.EshopReviewLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.Pricing
  alias Dockd.Pricing.StoreListing
  alias Dockd.Repo

  setup :register_and_log_in_user

  # The Swords of Ditto as the real sync left it on 27/09/2026: a prefix and a bundle.
  @candidates [
    %{
      "external_id" => "70010000017137",
      "title" => "The Swords of Ditto: Mormo's Curse",
      "class" => "prefix",
      "platform" => "switch",
      "bundle" => false,
      "url" => "/pt-br/store/products/the-swords-of-ditto-mormos-curse-switch/",
      "sales_status" => "onsale",
      "regular_cents" => 4_699,
      "currency" => "BRL",
      "seen_at" => "2026-09-27T21:00:00.000000Z"
    },
    %{
      "external_id" => "70070000028312",
      "title" => "The Plucky Squire x The Swords of Ditto: Mormo's Curse Bundle",
      "class" => "contains",
      "platform" => "switch",
      "bundle" => true,
      "sales_status" => "onsale",
      "regular_cents" => 11_000,
      "currency" => "BRL",
      "seen_at" => "2026-09-27T21:00:00.000000Z"
    }
  ]

  setup do
    game = game_fixture(%{title: "The Swords of Ditto"})
    release = release_fixture(game, %{platform: :switch})

    listing =
      %StoreListing{release_id: release.id}
      |> StoreListing.changeset(%{store: :eshop_br, match: :review, candidates: @candidates})
      |> Repo.insert!()

    %{game: game, release: release, listing: listing, row: "#match-#{listing.id}"}
  end

  test "the account menu leads to the queue while something waits", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#account-eshop-review[href='/eshop']", "Escolher na eShop")
    assert has_element?(view, "#account-eshop-review small", "1")

    {:ok, _} = Pricing.reject_listing(ctx.listing)
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#account-eshop-review")
  end

  test "shows each candidate with its price in Brazil", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/eshop")

    assert has_element?(view, "#eshop-review-head", "1")
    assert has_element?(view, "#{ctx.row} .dk-row__meta", "Switch · 2 candidatos")

    mormo = "#{ctx.row}-70010000017137"

    assert has_element?(
             view,
             "#{mormo} a[href='https://www.nintendo.com/pt-br/store/products/the-swords-of-ditto-mormos-curse-switch/']"
           )

    assert has_element?(view, "#{mormo} .dk-price", "R$ 46,99")
    assert has_element?(view, "#{ctx.row}-70070000028312 .dk-row__meta", "Pacote · Switch")
  end

  test "É este prices the version in place, and Desfazer brings the candidates back",
       %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/eshop")

    view |> element("#{ctx.row}-70010000017137 button", "É este") |> render_click()

    assert has_element?(view, "#{ctx.row}[data-state=confirmed]")
    assert has_element?(view, "#{ctx.row} .dk-row__meta", "Mormo's Curse")
    assert has_element?(view, "#{ctx.row} .dk-price", "R$ 46,99")
    assert has_element?(view, "#eshop-review-head", "0")
    assert %{price_cents: 4_699, source: "eShop"} = Pricing.store_price(ctx.release.id)

    view |> element("#{ctx.row}-undo") |> render_click()

    assert has_element?(view, "#{ctx.row}[data-state=review]")
    assert has_element?(view, "#{ctx.row}-70010000017137")
    assert Pricing.store_price(ctx.release.id) == nil
    assert has_element?(view, "#eshop-review-head", "1")
  end

  test "Não está na eShop takes the version out, and Desfazer puts it back",
       %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/eshop")

    view |> element("#{ctx.row}-none") |> render_click()

    assert has_element?(view, "#{ctx.row} .dk-row__meta", "fora da eShop")
    refute has_element?(view, "#{ctx.row}-70010000017137")
    assert %{match: :rejected} = Repo.get!(StoreListing, ctx.listing.id)

    view |> element("#{ctx.row}-undo") |> render_click()
    assert %{match: :review} = Repo.get!(StoreListing, ctx.listing.id)
  end

  test "a product another version already uses says so under the row", %{conn: conn} = ctx do
    other = release_fixture(game_fixture(%{title: "Other"}), %{platform: :switch})

    %StoreListing{release_id: other.id}
    |> StoreListing.changeset(%{store: :eshop_br, match: :auto, external_id: "70010000017137"})
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/eshop")
    view |> element("#{ctx.row}-70010000017137 button", "É este") |> render_click()

    assert has_element?(view, "#{ctx.row} .dk-match__error", "Outra versão já usa este")
    assert %{match: :review} = Repo.get!(StoreListing, ctx.listing.id)
  end

  test "an empty queue says so", %{conn: conn} = ctx do
    {:ok, _} = Pricing.reject_listing(ctx.listing)
    {:ok, view, _html} = live(conn, ~p"/eshop")

    assert has_element?(view, "#eshop-review-empty", "Nada para escolher na eShop.")
  end

  test "a visitor is sent to Entrar" do
    assert {:error, {:redirect, %{to: "/entrar" <> _}}} = live(build_conn(), ~p"/eshop")
  end
end
