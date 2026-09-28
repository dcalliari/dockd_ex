alias Dockd.Accounts
alias Dockd.Catalog
alias Dockd.Library
alias Dockd.Pricing.{StoreListing, StorePrice}
alias Dockd.Purchasing
alias Dockd.Repo

Ecto.Adapters.SQL.query!(
  Repo,
  "TRUNCATE users_tokens, store_prices, store_listings, events, price_observations, purchases, ownerships, release_vetoes, entries, releases, games, users RESTART IDENTITY CASCADE"
)

{:ok, owner} = Accounts.register_user(%{email: "e2e@dockd.local", password: "senha-da-jornada-e2e"})
owner = Repo.update!(Ecto.Changeset.change(owner, admin: true))
today = Date.utc_today()
cover_url = "/images/e2e-cover.svg"

create_game = fn title, release_date, attrs ->
  {:ok, game} =
    Catalog.create_game(
      Map.merge(
        %{
          title: title,
          cover_url: cover_url,
          availability: :nintendo_exclusive,
          pace: :normal,
          play_mode: :solo,
          estimated_duration_minutes: 30
        },
        attrs
      )
    )

  {:ok, release} =
    Catalog.create_release(game.id, %{
      platform: :switch,
      release_date: release_date,
      edition: "Edição padrão",
      physical_available: true,
      digital_available: true
    })

  %{game: game, release: release}
end

owned_games =
  Enum.map(1..20, fn index ->
    title =
      case index do
        1 -> "Owned Adventure"
        2 -> "Owned Finished"
        _ -> "Owned Game #{index}"
      end

    data = create_game.(title, Date.add(today, -index * 30), %{})

    {:ok, _entry} =
      Library.create_entry(owner, %{
        game_id: data.game.id,
        purchase_intent: :none,
        play_state: if(index == 2, do: :finished, else: :unplayed),
        backlog: if(index == 2, do: :no, else: :backlog),
        priority: if(index == 1, do: :high, else: :normal),
        target_price_cents: nil
      })

    {:ok, _ownership} =
      Library.create_ownership(owner, %{
        release_id: data.release.id,
        ownership_type: if(rem(index, 2) == 0, do: :physical, else: :digital),
        acquired_at: DateTime.add(DateTime.utc_now(), -index * 86_400, :second)
      })

    data
  end)

future_alpha = create_game.("Future Alpha", Date.add(today, 20), %{})
future_beta = create_game.("Future Beta", Date.add(today, 10), %{})
future_veto = create_game.("Future Veto", Date.add(today, 40), %{})
buyable = create_game.("Buyable Quest", Date.add(today, -30), %{})
expensive = create_game.("Expensive Quest", Date.add(today, -25), %{})
mystery = create_game.("Mystery Quest", Date.add(today, -20), %{})
store_quest = create_game.("Store Quest", Date.add(today, -40), %{})
review_quest = create_game.("Review Quest", Date.add(today, -50), %{})

# The eShop price the daily sync would have recorded, on sale. Store Quest stays out of
# the library so the queue totals of the other journeys do not change.
now = DateTime.utc_now()

store_listing =
  %StoreListing{release_id: store_quest.release.id}
  |> StoreListing.changeset(%{
    store: :eshop_br,
    match: :auto,
    external_id: "70010000000001",
    title: "Store Quest",
    sales_status: "onsale",
    checked_at: now
  })
  |> Repo.insert!()

%StorePrice{listing_id: store_listing.id}
|> StorePrice.changeset(%{
  regular_cents: 19_990,
  discount_cents: 9_990,
  discount_starts_at: DateTime.add(now, -2, :day),
  discount_ends_at: DateTime.add(now, 12, :day),
  sales_status: "onsale",
  first_seen_at: now,
  last_seen_at: now
})
|> Repo.insert!()

# A game sold in three editions besides the standard one, out of the library like Store
# Quest: Versões shows the two cheapest under Switch and Comprei opens them with prices.
edition_quest = create_game.("Edition Quest", Date.add(today, -60), %{})

list_price = fn release, external_id, cents ->
  listing =
    %StoreListing{release_id: release.id}
    |> StoreListing.changeset(%{
      store: :eshop_br,
      match: :auto,
      external_id: external_id,
      sales_status: "onsale",
      checked_at: now
    })
    |> Repo.insert!()

  %StorePrice{listing_id: listing.id}
  |> StorePrice.changeset(%{
    regular_cents: cents,
    sales_status: "onsale",
    first_seen_at: now,
    last_seen_at: now
  })
  |> Repo.insert!()
end

list_price.(edition_quest.release, "70010000000010", 19_990)

for {edition, external_id, cents} <- [
      {"Deluxe Edition", "70070000000011", 24_990},
      {"Gold Edition", "70070000000012", 29_990},
      {"Ultimate Edition", "70070000000013", 34_990}
    ] do
  {:ok, release} =
    Catalog.create_release(edition_quest.game.id, %{
      platform: :switch,
      release_date: edition_quest.release.release_date,
      edition: edition,
      digital_available: true
    })

  list_price.(release, external_id, cents)
end

# A game and another IGDB entry, here as its own game, that may be the same one: the
# first question of Conferir catálogo.
calamity = create_game.("Calamity Warriors", Date.add(today, -700), %{igdb_id: 900_001})

create_game.("Calamity Warriors: Definitive Edition", Date.add(today, 200), %{
  igdb_id: 900_002
})

Repo.insert!(%Dockd.Catalog.GameLink{
  igdb_id: 900_002,
  game_id: calamity.game.id,
  kind: :expanded,
  match: :review
})

# A version the sync could not settle, waiting in Conferir catálogo with two candidates.
%StoreListing{release_id: review_quest.release.id}
|> StoreListing.changeset(%{
  store: :eshop_br,
  match: :review,
  candidates: [
    %{
      "external_id" => "70010000000002",
      "title" => "Review Quest: Director's Edition",
      "class" => "prefix",
      "platform" => "switch",
      "bundle" => false,
      "sales_status" => "onsale",
      "regular_cents" => 4_699,
      "currency" => "BRL",
      "seen_at" => DateTime.to_iso8601(now)
    },
    %{
      "external_id" => "70070000000003",
      "title" => "Review Quest and Friends Bundle",
      "class" => "contains",
      "platform" => "switch",
      "bundle" => true,
      "sales_status" => "onsale",
      "regular_cents" => 11_000,
      "currency" => "BRL",
      "seen_at" => DateTime.to_iso8601(now)
    }
  ]
})
|> Repo.insert!()

for {data, target} <- [
      {future_alpha, 25_000},
      {future_beta, 30_000},
      {future_veto, 15_000},
      {buyable, 20_000},
      {expensive, 20_000},
      {mystery, 10_000}
    ] do
  {:ok, _entry} =
    Library.create_entry(owner, %{
      game_id: data.game.id,
      purchase_intent: :want,
      play_state: :unplayed,
      backlog: :no,
      priority: :high,
      target_price_cents: target
    })
end

{:ok, _buyable_observation} =
  Purchasing.create_price_observation(owner, %{
    release_id: buyable.release.id,
    format: :digital,
    price_cents: 10_000,
    currency: "BRL",
    observed_at: DateTime.add(DateTime.utc_now(), -86_400, :second),
    source: "e2e"
  })

{:ok, _expensive_observation} =
  Purchasing.create_price_observation(owner, %{
    release_id: expensive.release.id,
    format: :digital,
    price_cents: 30_000,
    currency: "BRL",
    observed_at: DateTime.add(DateTime.utc_now(), -86_400, :second),
    source: "e2e"
  })

for index <- 1..24 do
  data =
    create_game.("Wishlist Game #{index}", nil, %{
      availability: :multiplatform,
      other_platforms: ["PC"]
    })

  {:ok, _entry} =
    Library.create_entry(owner, %{
      game_id: data.game.id,
      purchase_intent: :interested,
      play_state: :unplayed,
      backlog: :no,
      priority: :low
    })
end

_discovery_candidate = create_game.("Discovery Candidate", nil, %{})
_visitor_pick = create_game.("Visitor Pick", Date.add(today, 60), %{})

IO.puts("Dockd E2E fixture loaded: #{length(owned_games)} owned games and 30 wishlist entries")
