defmodule Dockd.PricingTest do
  use Dockd.DataCase, async: false
  import ExUnit.CaptureLog
  import Dockd.DomainFixtures
  alias Dockd.{EshopStub, IGDB, Pricing, Purchasing}
  alias Dockd.Pricing.{CurrentPrice, StoreListing, StorePrice}
  alias Dockd.Purchasing.PriceObservation

  # Recorded from Nintendo on 2026-09-27, while Blasphemous 2 was on sale.
  @during_sale ~U[2026-09-27 12:00:00.000000Z]
  @after_sale ~U[2026-10-20 12:00:00.000000Z]

  setup do
    Application.put_env(:dockd, :eshop, EshopStub.config())
    EshopStub.stub(self())

    on_exit(fn ->
      Application.put_env(:dockd, :eshop, [])
      Application.put_env(:dockd, :igdb, [])
    end)

    :ok
  end

  defp game_with(title, platforms, attrs \\ %{}) do
    game = game_fixture(Map.merge(%{title: title}, attrs))
    releases = Map.new(platforms, &{&1, release_fixture(game, %{platform: &1})})
    {game, releases}
  end

  defp listing(release), do: Repo.get_by!(StoreListing, release_id: release.id)

  defp listing_for(nsuid) do
    {_game, %{switch: release}} = game_with("Listed #{nsuid}", [:switch])

    %StoreListing{release_id: release.id}
    |> StoreListing.changeset(%{store: :eshop_br, match: :auto, external_id: nsuid})
    |> Repo.insert!()
    |> Map.put(:release, release)
  end

  defp searches do
    receive do
      {:eshop_request, :search, detail, _agent} -> [detail | searches()]
    after
      0 -> []
    end
  end

  describe "match_eshop/0" do
    test "accepts exact and edition titles for each platform, never the upgrade pack" do
      {_, zelda} =
        game_with("The Legend of Zelda: Tears of the Kingdom", [:switch, :switch_2])

      {_, %{switch: rayman}} = game_with("Rayman Legends", [:switch])
      {_, %{switch_2: pokopia}} = game_with("Pokémon Pokopia", [:switch_2])

      assert {:ok, %{auto: 4, review: 0, none: 0}} = Pricing.match_eshop()

      assert %{match: :auto, external_id: "70010000063714"} = listing(zelda.switch)

      assert %{match: :auto, external_id: "70010000096821", title: title} =
               listing(zelda.switch_2)

      assert title =~ "Nintendo Switch™ 2 Edition"
      assert %{match: :auto, external_id: "70010000001017"} = listing(rayman)
      # Missing from the Brazilian index, found in the American one.
      assert %{match: :auto, external_id: "70010000107421"} = listing(pokopia)

      refute Repo.exists?(from l in StoreListing, where: like(l.external_id, "7005%"))
    end

    test "an empty app id, as compose passes it, falls back to nintendo.com's" do
      Application.put_env(:dockd, :eshop, EshopStub.config(algolia_app_id: ""))
      game_with("Rayman Legends", [:switch])

      assert {:ok, %{auto: 1}} = Pricing.match_eshop()
      assert_received {:eshop_request, :search, {"store_game_pt_br", "Rayman Legends"}, _}
    end

    test "stops searching once every platform has a safe match" do
      game_with("The Legend of Zelda: Tears of the Kingdom", [:switch, :switch_2])
      Pricing.match_eshop()

      assert searches() == [{"store_game_pt_br", "The Legend of Zelda: Tears of the Kingdom"}]
    end

    test "searches a release in review again, accepting a safe match that appears later" do
      {_, %{switch_2: release}} = game_with("Pokémon Pokopia", [:switch_2])

      %StoreListing{release_id: release.id}
      |> StoreListing.changeset(%{
        store: :eshop_br,
        match: :review,
        candidates: [%{"external_id" => "70010000039945", "title" => "Pokémon™ Legends: Arceus"}]
      })
      |> Repo.insert!()

      assert {:ok, %{auto: 1}} = Pricing.match_eshop()

      assert %{match: :auto, external_id: "70010000107421", candidates: []} = listing(release)
      assert Repo.aggregate(StoreListing, :count) == 1
    end

    test "leaves confirmed and rejected listings alone" do
      {_, %{switch: release}} = game_with("Rayman Legends", [:switch])

      %StoreListing{release_id: release.id}
      |> StoreListing.changeset(%{store: :eshop_br, match: :rejected})
      |> Repo.insert!()

      assert {:ok, %{auto: 0, review: 0, none: 0}} = Pricing.match_eshop()
      assert searches() == []
    end

    test "searches IGDB alternative names when the store uses a translated title" do
      Application.put_env(:dockd, :igdb,
        client_id: "id",
        client_secret: "secret",
        req_options: [plug: {Req.Test, "pricing-igdb"}]
      )

      IGDB.clear_cache()

      Req.Test.stub("pricing-igdb", fn conn ->
        case conn.request_path do
          "/oauth2/token" ->
            Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

          "/v4/games" ->
            Req.Test.json(conn, [
              %{
                "id" => 119_388,
                "alternative_names" => [%{"name" => "Indiana Jones e o Grande Círculo"}]
              }
            ])
        end
      end)

      {_, %{switch_2: release}} =
        game_with("Indiana Jones and the Great Circle", [:switch_2], %{igdb_id: 119_388})

      Pricing.match_eshop()

      assert %{match: :auto, external_id: "70010000098812"} = listing(release)
    end

    test "sends prefixes and weak titles to review with up to three candidates" do
      {_, %{switch: ditto}} = game_with("The Swords of Ditto", [:switch])
      {_, %{switch: ff}} = game_with("Final Fantasy XV", [:switch])
      {_, %{switch: tmnt}} = game_with("Splintered Fate", [:switch])
      {_, %{switch: borderlands}} = game_with("Borderlands 2", [:switch])

      assert {:ok, %{auto: 0, review: 4}} = Pricing.match_eshop()

      assert %{match: :review, external_id: nil, candidates: [first | _]} = listing(ditto)

      # The price in Brazil comes with the candidate, so choosing needs no second look.
      assert %{
               "external_id" => "70010000017137",
               "title" => "The Swords of Ditto: Mormo's Curse",
               "class" => "prefix",
               "platform" => "switch",
               "bundle" => false,
               "sales_status" => "onsale",
               "regular_cents" => 4_699
             } = first

      # A prefix can be another game: never accepted on its own.
      assert %{match: :review, candidates: [%{"external_id" => "70010000009443"}]} = listing(ff)

      # Only the base game: bundles with DLC and add-ons are left out.
      assert %{match: :review, candidates: [%{"external_id" => "70010000078903"}]} =
               listing(tmnt)

      assert %{match: :review, candidates: candidates} = listing(borderlands)
      assert length(candidates) == 3
      assert Enum.all?(candidates, &(&1["class"] == "weak"))
    end

    test "fails visibly when the search key is refused, and prices still sync" do
      refused = EshopStub.fixture("algolia_invalid_key.json")

      Req.Test.stub(EshopStub.name(), fn
        %{host: "api.ec.nintendo.com"} = conn ->
          Req.Test.json(conn, %{"prices" => EshopStub.recorded_prices() |> Enum.take(1)})

        conn ->
          conn |> Plug.Conn.put_status(403) |> Req.Test.json(refused)
      end)

      listed = listing_for("70010000063714")
      game_with("Rayman Legends", [:switch])

      log =
        capture_log(fn ->
          assert %{match: {:error, {:http_error, 403}}, prices: {:ok, %{priced: 1}}} =
                   Pricing.sync_eshop(@during_sale)
        end)

      assert log =~ "eShop: casamento falhou"
      assert %{price_cents: 38_990} = Pricing.store_price(listed.release.id)
    end
  end

  describe "review" do
    setup do
      {_, %{switch: ditto}} = game_with("The Swords of Ditto", [:switch])
      {:ok, %{review: 1}} = Pricing.match_eshop()
      %{ditto: ditto, listing: listing(ditto)}
    end

    test "lists what waits, with its game", %{listing: listing} do
      assert [%StoreListing{id: id, release: %{game: %{title: "The Swords of Ditto"}}}] =
               Pricing.list_review_listings()

      assert id == listing.id
      assert Pricing.review_count() == 1
    end

    test "confirming a candidate prices the release at once", %{ditto: ditto, listing: listing} do
      assert {:ok, %{match: :confirmed, external_id: "70010000017137"}} =
               Pricing.confirm_listing(listing, "70010000017137")

      assert %CurrentPrice{price_cents: 4_699, source: "eShop"} = Pricing.store_price(ditto.id)
      assert Pricing.review_count() == 0

      # The daily sync keeps pricing it and does not search it again.
      assert {:ok, %{auto: 0, review: 0}} = Pricing.match_eshop()
      assert {:ok, %{listings: 1, priced: 1}} = Pricing.sync_eshop_prices()
    end

    test "only a listed candidate can be confirmed", %{listing: listing} do
      assert Pricing.confirm_listing(listing, "70010000063714") == {:error, :not_a_candidate}
    end

    test "rejecting takes the release out of the queue for good", %{
      ditto: ditto,
      listing: listing
    } do
      assert {:ok, %{match: :rejected}} = Pricing.reject_listing(listing)
      assert Pricing.list_review_listings() == []
      assert Pricing.store_price(ditto.id) == nil
      assert {:ok, %{review: 0}} = Pricing.match_eshop()
    end

    test "undo puts a confirmed or rejected listing back in review", %{
      ditto: ditto,
      listing: listing
    } do
      {:ok, confirmed} = Pricing.confirm_listing(listing, "70010000017137")
      assert {:ok, %{match: :review, external_id: nil}} = Pricing.reopen_listing(confirmed)
      assert Pricing.store_price(ditto.id) == nil
      assert Repo.aggregate(StorePrice, :count) == 0

      {:ok, rejected} = Pricing.reject_listing(listing(ditto))
      assert {:ok, %{match: :review}} = Pricing.reopen_listing(rejected)
      assert Pricing.review_count() == 1
    end

    test "a candidate shows what it cost when found", %{listing: listing} do
      [mormo, bundle] = listing.candidates

      assert %CurrentPrice{price_cents: 4_699} = Pricing.candidate_price(mormo)
      assert %CurrentPrice{price_cents: 11_000} = Pricing.candidate_price(bundle)
      assert Pricing.candidate_price(%{"external_id" => "1"}) == nil
    end
  end

  describe "sync_eshop_prices/1" do
    test "the Brazilian price API decides the sales status" do
      {_, %{switch: firewatch}} = game_with("Firewatch", [:switch])
      Pricing.match_eshop()
      assert %{match: :auto, external_id: "70010000007926"} = listing(firewatch)

      {:ok, %{listings: 1, priced: 0}} = Pricing.sync_eshop_prices(@during_sale)

      assert %{sales_status: "not_found", checked_at: @during_sale} = listing(firewatch)
      assert Pricing.store_price(firewatch.id) == nil
    end

    test "records changes only, moving last_seen_at while nothing changes" do
      zelda = listing_for("70010000063714")
      unreleased = listing_for("70010000126640")

      assert {:ok, %{listings: 2, priced: 1, changed: 2}} =
               Pricing.sync_eshop_prices(@during_sale)

      later = DateTime.add(@during_sale, 1, :day)
      assert {:ok, %{changed: 0}} = Pricing.sync_eshop_prices(later)

      assert [
               %StorePrice{
                 regular_cents: 38_990,
                 first_seen_at: @during_sale,
                 last_seen_at: ^later
               }
             ] =
               Repo.all(from p in StorePrice, where: p.listing_id == ^zelda.id)

      assert [%StorePrice{sales_status: "unreleased", regular_cents: nil}] =
               Repo.all(from p in StorePrice, where: p.listing_id == ^unreleased.id)

      cheaper =
        Enum.map(EshopStub.recorded_prices(), fn
          %{"title_id" => 70_010_000_063_714} = price ->
            put_in(price, ["regular_price", "raw_value"], "299.9")

          price ->
            price
        end)

      EshopStub.stub(self(), cheaper)
      next = DateTime.add(later, 1, :day)
      assert {:ok, %{changed: 1}} = Pricing.sync_eshop_prices(next)

      assert [38_990, 29_990] =
               Repo.all(
                 from p in StorePrice,
                   where: p.listing_id == ^zelda.id,
                   order_by: p.first_seen_at,
                   select: p.regular_cents
               )
    end

    test "asks at most 50 nsuids per request, identifying Dockd" do
      ids = Enum.map(EshopStub.recorded_prices(), &to_string(&1["title_id"]))
      prices = EshopStub.recorded_prices()

      # 80 listings whatever the recording's size: two requests, the second partial.
      many =
        for n <- 1..(80 - length(ids)) do
          id = "7001#{String.pad_leading(Integer.to_string(n), 10, "0")}"
          %{"title_id" => String.to_integer(id), "sales_status" => "unreleased"}
        end

      EshopStub.stub(self(), prices ++ many)
      Enum.each(ids ++ Enum.map(many, &to_string(&1["title_id"])), &listing_for/1)

      {:ok, %{listings: 80}} = Pricing.sync_eshop_prices(@during_sale)

      assert_received {:eshop_request, :price, first, agent}
      assert_received {:eshop_request, :price, second, _}
      assert {length(first), length(second)} == {50, 30}
      assert agent =~ ~r{^Dockd/[\x20-\x7e]+$}
    end

    test "logs an error when Nintendo fails or no price comes back" do
      listing_for("70010000063714")

      Req.Test.stub(EshopStub.name(), fn conn ->
        conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "gone"})
      end)

      assert capture_log(fn ->
               assert %{prices: {:error, {:http_error, 404}}} = Pricing.sync_eshop(@during_sale)
             end) =~ "eShop: preços falhou"

      EshopStub.stub(self(), [
        %{"title_id" => 70_010_000_063_714, "sales_status" => "not_found"}
      ])

      assert capture_log(fn -> Pricing.sync_eshop(@during_sale) end) =~
               "eShop: nenhum preço para 1 produtos"
    end

    test "an unexpected answer is logged, not raised" do
      listing_for("70010000063714")
      Req.Test.stub(EshopStub.name(), &Req.Test.text(&1, "<html>maintenance</html>"))

      assert capture_log(fn ->
               assert %{prices: {:error, :unexpected_response}} = Pricing.sync_eshop()
             end) =~ "eShop: preços falhou"
    end
  end

  describe "the daily scheduler" do
    test "prices after the IGDB sync, which a Nintendo failure leaves intact" do
      title = "The Legend of Zelda: Tears of the Kingdom"

      Req.Test.stub("pricing-igdb", fn conn ->
        case conn.request_path do
          "/oauth2/token" ->
            Req.Test.json(conn, %{access_token: "token", expires_in: 3600})

          # The search, the sync and the alternative names all find the same work.
          "/v4/games" ->
            Req.Test.json(conn, [%{"id" => 88, "name" => title, "platforms" => [%{"id" => 130}]}])
        end
      end)

      Application.put_env(:dockd, :igdb,
        client_id: "id",
        client_secret: "secret",
        sync_initial_delay: 60_000,
        sync_interval: 60_000,
        req_options: [plug: {Req.Test, "pricing-igdb"}]
      )

      IGDB.clear_cache()

      Req.Test.stub(EshopStub.name(), fn
        %{host: "api.ec.nintendo.com"} = conn ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "gone"})

        conn ->
          conn
          |> Req.Test.json(
            EshopStub.fixture("store_game_pt_br--the-legend-of-zelda-tears-of-the-kingdom.json")
          )
      end)

      game = game_fixture(%{title: title})
      scheduler = start_supervised!(Dockd.IGDB.SyncScheduler)

      assert capture_log(fn ->
               send(scheduler, :initial_sync)
               _ = :sys.get_state(scheduler)
             end) =~ "eShop: preços falhou"

      assert %{igdb_id: 88, releases: [release]} = Dockd.Catalog.get_game!(game.id)
      assert %{match: :auto, external_id: "70010000063714"} = listing(release)
      assert Pricing.store_price(release.id) == nil
    end
  end

  describe "store_price/2" do
    test "uses the discount only inside its window" do
      blasphemous = listing_for("70010000062593")
      {:ok, _} = Pricing.sync_eshop_prices(@during_sale)

      assert %CurrentPrice{
               price_cents: 3_997,
               regular_cents: 15_990,
               discount_ends_at: ~U[2026-10-17 06:59:59.000000Z],
               source: "eShop",
               format: :digital,
               observed_at: @during_sale
             } = Pricing.store_price(blasphemous.release.id, @during_sale)

      assert %CurrentPrice{price_cents: 15_990, discount_ends_at: nil} =
               Pricing.store_price(blasphemous.release.id, @after_sale)
    end

    test "a store price stays fresh while the sync runs and goes stale when it stops" do
      zelda = listing_for("70010000063714")
      {:ok, _} = Pricing.sync_eshop_prices(@during_sale)
      price = Pricing.store_price(zelda.release.id)

      refute Purchasing.stale?(price, DateTime.add(@during_sale, 1, :day))
      assert Purchasing.stale?(price, DateTime.add(@during_sale, 8, :day))
    end
  end

  describe "Purchasing.current_price/3" do
    setup do
      {:ok, user} = user_fixture()
      %{user: user}
    end

    test "is the eShop price for the digital copy, the user's for the physical one", %{
      user: user
    } do
      zelda = listing_for("70010000063714")
      {:ok, _} = Pricing.sync_eshop_prices(DateTime.utc_now())
      observe(user, zelda.release, 10_000, :physical)
      observe(user, zelda.release, 20_000, :digital)

      assert %CurrentPrice{price_cents: 38_990, source: "eShop"} =
               Purchasing.current_price(user, zelda.release.id)

      assert %CurrentPrice{price_cents: 38_990} =
               Purchasing.current_price(user, zelda.release.id, :digital)

      assert %PriceObservation{price_cents: 10_000, source: "OLX"} =
               Purchasing.current_price(user, zelda.release.id, :physical)
    end

    test "falls back to the user's observation when the eShop does not sell it", %{user: user} do
      {_, %{switch: unlisted}} = game_with("Only physical", [:switch])
      terminated = listing_for("70010000083034")
      {:ok, _} = Pricing.sync_eshop_prices(@during_sale)

      observe(user, unlisted, 19_990, :physical)
      observe(user, terminated.release, 12_000, :digital)

      assert %PriceObservation{price_cents: 19_990} = Purchasing.current_price(user, unlisted.id)

      assert %PriceObservation{price_cents: 12_000} =
               Purchasing.current_price(user, terminated.release.id, :digital)

      assert Purchasing.current_price(user, unlisted.id, :digital) == nil
    end
  end

  defp observe(user, release, cents, format) do
    {:ok, _} =
      Purchasing.create_price_observation(user, %{
        release_id: release.id,
        format: format,
        price_cents: cents,
        observed_at: DateTime.add(@during_sale, -1, :day),
        source: "OLX"
      })
  end
end
