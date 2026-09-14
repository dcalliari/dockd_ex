alias Dockd.Accounts
alias Dockd.Catalog
alias Dockd.Library
alias Dockd.Purchasing
alias Dockd.Wallet

# Seeds are intentionally idempotent. Use only against a throwaway database.
if Catalog.list_games() == [] do
  owner = Accounts.default_owner()

  catalog = [
    {"The Legend of Zelda: Tears of the Kingdom", :nintendo_exclusive, :demanding, :solo, 120,
     :switch, "2023-05-12", true, true, false},
    {"Super Mario Bros. Wonder", :nintendo_exclusive, :normal, :multi, 15, :switch, "2023-10-20",
     true, true, false},
    {"Mario Kart World", :switch2_exclusive, :normal, :multi, 60, :switch_2, "2025-06-05", false,
     true, false},
    {"Donkey Kong Bananza", :switch2_exclusive, :demanding, :solo, 25, :switch_2, "2025-07-17",
     true, true, false},
    {"Metroid Prime 4: Beyond", :nintendo_exclusive, :demanding, :solo, 40, :switch, "2025-12-04",
     true, true, true},
    {"Hades II", :multiplatform, :demanding, :both, 35, :switch_2, "2025-09-25", false, true,
     false},
    {"Hollow Knight: Silksong", :multiplatform, :demanding, :solo, 30, :switch_2, "2026-12-04",
     false, true, false},
    {"Balatro", :multiplatform, :relaxing, :solo, 20, :switch, "2024-02-20", false, true, false},
    {"Pikmin 4", :nintendo_exclusive, :relaxing, :both, 25, :switch, "2023-07-21", true, true,
     false},
    {"Animal Crossing: New Horizons", :nintendo_exclusive, :relaxing, :multi, 80, :switch,
     "2020-03-20", true, true, false},
    {"Sea of Stars", :multiplatform, :normal, :both, 30, :switch, "2023-08-29", true, true,
     false},
    {"Fire Emblem Engage", :nintendo_exclusive, :normal, :solo, 45, :switch, "2023-01-20", true,
     true, false}
  ]

  games =
    Enum.map(catalog, fn {title, availability, pace, mode, duration, platform, date, physical,
                          digital, key_card} ->
      {:ok, game} =
        Catalog.create_game(%{
          title: title,
          availability: availability,
          pace: pace,
          play_mode: mode,
          estimated_duration_minutes: duration,
          other_platforms: if(availability == :multiplatform, do: ["PC"], else: [])
        })

      {:ok, release} =
        Catalog.create_release(game.id, %{
          platform: platform,
          release_date: date && Date.from_iso8601!(date),
          edition: "Edição padrão",
          physical_available: physical,
          digital_available: digital,
          physical_is_key_card: key_card
        })

      %{game: game, release: release}
    end)

  Enum.each(Enum.with_index(games), fn {%{game: game, release: release}, index} ->
    intents = [:want, :planned, :interested, :none, :preordered]
    states = [:unplayed, :playing, :paused, :finished, :abandoned]
    backlogs = [:backlog, :active, :no]
    priorities = [:high, :normal, :low]

    {:ok, _entry} =
      Library.create_entry(owner, %{
        game_id: game.id,
        purchase_intent: Enum.at(intents, rem(index, 5)),
        play_state: Enum.at(states, rem(index, 5)),
        backlog: Enum.at(backlogs, rem(index, 3)),
        priority: Enum.at(priorities, rem(index, 3)),
        media_preference: if(rem(index, 2) == 0, do: :physical_preferred, else: :either),
        target_price_cents: 1500 + index * 500,
        currency: "BRL",
        owned_elsewhere: rem(index, 4) == 0
      })

    {:ok, _observation} =
      Purchasing.create_price_observation(owner, %{
        release_id: release.id,
        format: :digital,
        price_cents: 1990 + index * 700,
        currency: "BRL",
        observed_at:
          DateTime.add(DateTime.utc_now(), if(rem(index, 4) == 0, do: -20, else: -2), :day),
        source: if(rem(index, 2) == 0, do: "eShop", else: "loja")
      })
  end)

  first = Enum.at(games, 1)
  preorder = Enum.at(games, 2)

  {:ok, _purchase} =
    Purchasing.create_purchase(owner, %{
      release_id: first.release.id,
      format: :digital,
      price_cents: 5990,
      currency: "BRL",
      purchased_at: DateTime.add(DateTime.utc_now(), -30, :day),
      retailer: "Nintendo eShop",
      is_preorder: false
    })

  {:ok, _purchase} =
    Purchasing.create_purchase(owner, %{
      release_id: preorder.release.id,
      format: :digital,
      price_cents: 6990,
      currency: "BRL",
      purchased_at: DateTime.utc_now(),
      retailer: "Nintendo eShop",
      is_preorder: true
    })

  {:ok, _balance} =
    Wallet.create_balance(owner, %{store: :eshop, amount_cents: 10000, currency: "BRL"})

  {:ok, _reservation} =
    Wallet.create_reservation(owner, %{
      store: :eshop,
      game_id: preorder.game.id,
      amount_cents: 6990,
      note: "Reserva da pré-venda"
    })

  veto = Enum.at(games, 5)

  {:ok, _veto} =
    Library.create_veto(owner, %{release_id: veto.release.id, reason: "Prefiro jogar no PC"})

  IO.puts("Dockd demo data seeded: #{length(games)} games")
else
  IO.puts("Dockd seeds already present; nothing to do")
end
