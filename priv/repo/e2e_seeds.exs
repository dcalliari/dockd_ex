alias Dockd.Accounts
alias Dockd.Catalog
alias Dockd.Library
alias Dockd.Purchasing
alias Dockd.Repo
alias Dockd.Wallet

Ecto.Adapters.SQL.query!(
  Repo,
  "TRUNCATE events, balance_reservations, store_balances, price_observations, purchases, ownerships, release_vetoes, entries, releases, games, users RESTART IDENTITY CASCADE"
)

owner = Accounts.default_owner()
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

{:ok, _balance} = Wallet.create_balance(owner, %{store: :eshop, amount_cents: 30_000, currency: "BRL"})

{:ok, _reservation} =
  Wallet.create_reservation(owner, %{
    store: :eshop,
    game_id: future_alpha.game.id,
    amount_cents: 35_000,
    note: "Reserva de teste"
  })

IO.puts("Dockd E2E fixture loaded: #{length(owned_games)} owned games and 30 wishlist entries")
