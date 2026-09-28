defmodule DockdWeb.CatalogReviewLiveTest do
  use DockdWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Dockd.DomainFixtures

  alias Dockd.{Catalog, Library, Pricing, Repo}
  alias Dockd.Catalog.{Game, GameLink}
  alias Dockd.Library.Shelf
  alias Dockd.Pricing.StoreListing

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
    assert has_element?(view, "#account-catalog-review[href='/conferir']", "Conferir catálogo")
    assert has_element?(view, "#account-catalog-review small", "1")

    %{link: link} = same_game_fixture()
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#account-catalog-review small", "2")

    {:ok, _} = Pricing.reject_listing(ctx.listing)
    {:ok, _} = Catalog.reject_game_link(link)
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#account-catalog-review")
  end

  test "the old address still opens the queue", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/eshop")
    assert has_element?(view, ctx.row)
  end

  test "shows each candidate with its price in Brazil", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, ~p"/conferir")

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
    {:ok, view, _html} = live(conn, ~p"/conferir")

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
    {:ok, view, _html} = live(conn, ~p"/conferir")

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

    {:ok, view, _html} = live(conn, ~p"/conferir")
    view |> element("#{ctx.row}-70010000017137 button", "É este") |> render_click()

    assert has_element?(view, "#{ctx.row} .dk-match__error", "Outra versão já usa este")
    assert %{match: :review} = Repo.get!(StoreListing, ctx.listing.id)
  end

  test "an empty queue says so", %{conn: conn} = ctx do
    {:ok, _} = Pricing.reject_listing(ctx.listing)
    {:ok, view, _html} = live(conn, ~p"/conferir")

    assert has_element?(view, "#catalog-review-empty", "Nada para conferir.")
    refute has_element?(view, "#eshop-review-head")
    refute has_element?(view, "#same-game-head")
  end

  test "a visitor is sent to Entrar" do
    assert {:error, {:redirect, %{to: "/entrar" <> _}}} = live(build_conn(), ~p"/conferir")
  end

  describe "Mesmo jogo?" do
    setup ctx do
      fixture = same_game_fixture()
      {:ok, _} = Library.set_status(ctx.user, fixture.definitive, :quero)
      Map.put(fixture, :row, "#same-#{fixture.link.id}")
    end

    test "comes before the eShop, with the game and the entry that may be it",
         %{conn: conn} = ctx do
      {:ok, view, html} = live(conn, ~p"/conferir")

      assert has_element?(view, "#same-game-head", "Mesmo jogo?")
      assert has_element?(view, "#same-game-head", "1")
      assert :binary.match(html, "same-game-head") < :binary.match(html, "eshop-review-head")

      assert has_element?(view, "#{ctx.row} > .dk-row .dk-row__title", "Age of Calamity")

      assert has_element?(
               view,
               "#{ctx.row} > .dk-row .dk-row__meta",
               "Switch · 2020 · Omega Force · mesmo jogo?"
             )

      assert has_element?(
               view,
               "#{ctx.row} .dk-same__candidate .dk-row__meta",
               "Switch 2 · 2027 · expandido · Quero"
             )
    end

    test "É o mesmo jogo joins them in place, and Desfazer puts them apart",
         %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/conferir")

      view |> element("#{ctx.row}-same") |> render_click()

      assert has_element?(view, "#{ctx.row}[data-state=same]")
      assert has_element?(view, "#{ctx.row} .dk-row__meta", "Switch · Switch 2 · mesmo jogo")
      refute has_element?(view, "#{ctx.row} .dk-same__candidate")
      assert has_element?(view, "#same-game-head", "0")
      refute Repo.get(Game, ctx.definitive.id)
      assert Shelf.item(ctx.user, Catalog.get_game!(ctx.aoc.id)).status == :quero

      view |> element("#{ctx.row}-undo") |> render_click()

      assert has_element?(view, "#{ctx.row}[data-state=review]")
      assert has_element?(view, "#{ctx.row} .dk-same__candidate")
      assert has_element?(view, "#same-game-head", "1")
      assert Shelf.item(ctx.user, Repo.get!(Game, ctx.definitive.id)).status == :quero
      assert %{match: :review} = Repo.get!(GameLink, ctx.link.id)
    end

    test "É outro jogo keeps both, and Desfazer asks again", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/conferir")

      view |> element("#{ctx.row}-other") |> render_click()

      assert has_element?(view, "#{ctx.row} .dk-row__meta", "jogos diferentes")
      assert %{match: :rejected} = Repo.get!(GameLink, ctx.link.id)
      assert Repo.get(Game, ctx.definitive.id)

      view |> element("#{ctx.row}-undo") |> render_click()
      assert has_element?(view, "#{ctx.row}-same")
      assert %{match: :review} = Repo.get!(GameLink, ctx.link.id)
    end

    test "an answer given elsewhere shows without Desfazer", %{conn: conn} = ctx do
      {:ok, view, _html} = live(conn, ~p"/conferir")
      {:ok, _, _undo} = Catalog.confirm_game_link(ctx.link)

      view |> element("#{ctx.row}-same") |> render_click()

      assert has_element?(view, "#{ctx.row}[data-state=same]")
      refute has_element?(view, "#{ctx.row}-undo")
    end
  end

  # Hyrule Warriors: Age of Calamity and its Definitive Edition, here as its own game,
  # waiting for a person as the IGDB family leaves an expanded game with a parent here.
  defp same_game_fixture do
    aoc =
      game_fixture(%{
        title: "Hyrule Warriors: Age of Calamity",
        developer: "Omega Force",
        igdb_id: 136_848
      })

    release_fixture(aoc, %{platform: :switch, release_date: ~D[2020-11-20]})

    definitive =
      game_fixture(%{
        title: "Hyrule Warriors: Age of Calamity – Definitive Edition",
        igdb_id: 400_001
      })

    release_fixture(definitive, %{platform: :switch_2, release_date: ~D[2027-02-25]})

    link =
      Repo.insert!(%GameLink{igdb_id: 400_001, game_id: aoc.id, kind: :expanded, match: :review})

    %{aoc: aoc, definitive: definitive, link: link}
  end
end
