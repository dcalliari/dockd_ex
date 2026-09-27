defmodule DockdWeb.PurchasingApiTest do
  use DockdWeb.ConnCase, async: false
  import OpenApiSpex.TestAssertions
  alias Dockd.{Activity, Catalog, Library, Purchasing, Repo}

  setup :register_api_user

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
  end

  test "purchase closes the intent and logs the cycle", %{
    release: release,
    user: user
  } do
    {:ok, entry} =
      Library.create_entry(user, %{game_id: release.game_id, purchase_intent: :want, backlog: :no})

    assert {:ok, purchase} =
             Purchasing.create_purchase(user, %{
               release_id: release.id,
               format: :digital,
               price_cents: 8_500,
               currency: "BRL",
               purchased_at: ~U[2026-09-22 12:00:00Z],
               retailer: "eShop"
             })

    assert Repo.get!(Library.Entry, entry.id).purchase_intent == :none
    assert Repo.get!(Library.Entry, entry.id).backlog == :backlog

    events = Activity.list_events(user)
    assert Enum.any?(events, &(&1.type == :purchased and &1.game_id == release.game_id))
    assert Enum.any?(events, &(&1.type == :intent_changed and &1.game_id == release.game_id))
    assert Enum.any?(events, &(&1.type == :backlogged and &1.game_id == release.game_id))
    assert purchase.price_cents == 8_500
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
