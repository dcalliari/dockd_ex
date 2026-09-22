defmodule DockdWeb.PurchasingApiTest do
  use DockdWeb.ConnCase, async: false
  import OpenApiSpex.TestAssertions
  alias Dockd.{Accounts, Activity, Catalog, Library, Purchasing, Repo, Wallet}

  setup do
    {:ok, game} = Catalog.create_game(%{title: "Pikmin", availability: :nintendo_exclusive})

    {:ok, release} =
      Catalog.create_release(game.id, %{platform: :switch, digital_available: true})

    %{release: release}
  end

  test "price, purchase, and veto routes return their contracts", %{conn: conn, release: release} do
    conn = put_req_header(conn, "content-type", "application/json")

    price =
      post(conn, ~p"/api/v1/releases/#{release.id}/price-observations", %{
        format: "digital",
        price_cents: 2990,
        observed_at: "2026-09-14T10:00:00Z",
        source: "eShop"
      })
      |> json_response(201)

    assert_schema(price, "PurchasingResponse", DockdWeb.ApiSpec.spec())

    purchase =
      post(conn, ~p"/api/v1/releases/#{release.id}/purchases", %{
        format: "digital",
        price_cents: 2990,
        purchased_at: "2026-09-14T10:00:00Z",
        retailer: "eShop"
      })
      |> json_response(201)

    assert_schema(purchase, "PurchasingResponse", DockdWeb.ApiSpec.spec())

    veto =
      post(conn, ~p"/api/v1/releases/#{release.id}/vetoes", %{reason: "Esperar"})
      |> json_response(201)

    assert_schema(veto, "PurchasingResponse", DockdWeb.ApiSpec.spec())
    assert Accounts.default_owner()
  end

  test "purchase closes the intent, credit, reservation, and event cycle", %{release: release} do
    user = Accounts.default_owner()

    {:ok, entry} =
      Library.create_entry(user, %{game_id: release.game_id, purchase_intent: :want, backlog: :no})

    {:ok, balance} =
      Wallet.create_balance(user, %{store: :eshop, amount_cents: 30_000, currency: "BRL"})

    {:ok, reservation} =
      Wallet.create_reservation(user, %{
        store: :eshop,
        game_id: release.game_id,
        amount_cents: 35_000
      })

    assert {:ok, purchase} =
             Purchasing.create_purchase(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: 8_500,
               currency: "BRL",
               store_credit_used_cents: 8_500,
               purchased_at: ~U[2026-09-22 12:00:00Z],
               retailer: "eShop"
             })

    assert Repo.get!(Library.Entry, entry.id).purchase_intent == :none
    assert Repo.get!(Library.Entry, entry.id).backlog == :backlog
    assert Repo.get!(Wallet.StoreBalance, balance.id).amount_cents == 21_500
    refute Repo.get(Wallet.BalanceReservation, reservation.id)

    events = Activity.list_events(user)
    assert Enum.any?(events, &(&1.type == :purchased and &1.game_id == release.game_id))
    assert Enum.any?(events, &(&1.type == :intent_changed and &1.game_id == release.game_id))
    assert Enum.any?(events, &(&1.type == :backlogged and &1.game_id == release.game_id))
    assert purchase.store_credit_used_cents == 8_500
  end

  test "purchasing routes return validation errors", %{conn: conn, release: release} do
    conn = put_req_header(conn, "content-type", "application/json")

    for path <- [
          ~p"/api/v1/releases/#{release.id}/price-observations",
          ~p"/api/v1/releases/#{release.id}/purchases"
        ] do
      response = post(conn, path, %{}) |> json_response(422)
      assert_schema(response, "ValidationError", DockdWeb.ApiSpec.spec())
    end

    response =
      post(conn, ~p"/api/v1/releases/#{Ecto.UUID.generate()}/vetoes", %{}) |> json_response(422)

    assert_schema(response, "ValidationError", DockdWeb.ApiSpec.spec())
  end
end
