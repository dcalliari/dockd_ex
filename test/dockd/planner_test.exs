defmodule Dockd.PlannerTest do
  use Dockd.DataCase
  alias Dockd.{Accounts, Catalog, Library, Planner, Purchasing, Wallet}
  alias Dockd.Activity.Event
  alias Dockd.Catalog.Game
  alias Dockd.Library.Entry
  import Dockd.DomainFixtures

  setup do
    {:ok, user} = Accounts.create_user(%{name: "Planner owner"})
    %{user: user}
  end

  test "summary calculates integer balance and reservations", %{user: user} do
    {:ok, _} = balance_fixture(user, %{amount_cents: 10_001, currency: "BRL"})
    game = game_fixture()

    {:ok, _} =
      Wallet.create_reservation(user, %{store: :eshop, game_id: game.id, amount_cents: 2_501})

    money = Planner.summary(user).money
    assert money.balance_cents == 10_001
    assert money.reserved_cents == 2_501
    assert money.free_cents == 7_500
    assert money.currency == "BRL"
  end

  test "calendar recommends reserving exclusives and waiting on multiplatform games", %{
    user: user
  } do
    exclusive = game_fixture(%{title: "Exclusive recommendation"})
    multi = game_fixture(%{title: "Multiplatform recommendation", availability: :multiplatform})

    {:ok, _} =
      Catalog.create_release(exclusive.id, %{platform: :switch, release_date: ~D[2026-12-01]})

    {:ok, _} =
      Catalog.create_release(multi.id, %{platform: :switch, release_date: ~D[2026-12-02]})

    {:ok, _} = Library.create_entry(user, %{game_id: exclusive.id, purchase_intent: :want})
    {:ok, _} = Library.create_entry(user, %{game_id: multi.id, purchase_intent: :want})

    assert Enum.map(Planner.upcoming_releases(user, ~D[2026-01-01]), & &1.recommendation) == [
             "reserve",
             "can_wait"
           ]
  end

  test "purchase opportunities explain buy, wait, and missing price", %{user: user} do
    buy_game = game_fixture(%{title: "Buy now"})
    wait_game = game_fixture(%{title: "Wait"})
    missing_game = game_fixture(%{title: "Missing price"})
    buy_release = release_fixture(buy_game, %{release_date: ~D[2026-01-01]})
    wait_release = release_fixture(wait_game, %{release_date: ~D[2026-01-01]})
    _missing_release = release_fixture(missing_game, %{release_date: ~D[2026-01-01]})

    {:ok, _} =
      Library.create_entry(user, %{
        game_id: buy_game.id,
        purchase_intent: :want,
        target_price_cents: 9_000
      })

    {:ok, _} =
      Library.create_entry(user, %{
        game_id: wait_game.id,
        purchase_intent: :want,
        target_price_cents: 9_000
      })

    {:ok, _} = Library.create_entry(user, %{game_id: missing_game.id, purchase_intent: :want})
    {:ok, _} = balance_fixture(user, %{amount_cents: 10_000})

    {:ok, _} =
      Purchasing.create_price_observation(user, %{
        release_id: buy_release.id,
        format: :digital,
        price_cents: 8_500,
        observed_at: DateTime.add(DateTime.utc_now(), -3_600, :second),
        source: "eShop"
      })

    {:ok, _} =
      Purchasing.create_price_observation(user, %{
        release_id: wait_release.id,
        format: :digital,
        price_cents: 9_500,
        observed_at: DateTime.add(DateTime.utc_now(), -3_600, :second),
        source: "eShop"
      })

    opportunities = Planner.purchase_opportunities(user, ~D[2026-02-01])
    by_title = Map.new(opportunities, &{&1.game.title, &1})

    assert by_title["Buy now"].verdict == :buy
    assert by_title["Buy now"].verdict_reason =~ "abaixo do alvo"
    assert by_title["Wait"].verdict == :wait
    assert by_title["Wait"].verdict_reason =~ "acima do alvo"
    assert by_title["Missing price"].verdict == :record_price
    assert by_title["Missing price"].verdict_reason == "Sem observação de preço."
  end

  test "calendar exposes reservations and negative free balance", %{user: user} do
    game = game_fixture(%{title: "Reserved launch"})

    {:ok, release} =
      Catalog.create_release(game.id, %{platform: :switch, release_date: ~D[2026-12-01]})

    {:ok, _} = Library.create_entry(user, %{game_id: game.id, purchase_intent: :want})
    {:ok, _} = balance_fixture(user, %{amount_cents: 30_000})

    {:ok, _} =
      Wallet.create_reservation(user, %{store: :eshop, game_id: game.id, amount_cents: 35_000})

    summary = Planner.summary(user, ~D[2026-01-01])

    assert summary.money.free_cents == -5_000
    assert [%{release: %{id: release_id}, reserved_cents: 35_000}] = summary.calendar
    assert release_id == release.id
  end

  test "calendar empty reason explains undated releases", %{user: user} do
    game = game_fixture(%{title: "Undated desire"})
    {:ok, _release} = Catalog.create_release(game.id, %{platform: :switch})
    {:ok, _} = Library.create_entry(user, %{game_id: game.id, purchase_intent: :want})

    summary = Planner.summary(user, ~D[2026-01-01])

    assert summary.calendar == []
    assert summary.calendar_empty_reason == "Seus desejos têm versões sem data de lançamento."
  end

  test "release date label preserves year and marks year-only placeholders" do
    assert Planner.release_date_label(~D[2027-12-31]) == "2027, a definir"
    assert Planner.release_date_label(~D[2027-12-15]) == "15/12/2027"
  end

  test "credit is not double counted in committed and out of pocket totals", %{user: user} do
    {:ok, _} = balance_fixture(user, %{amount_cents: 2_000, currency: "BRL"})
    game = game_fixture()
    release = release_fixture(game)

    {:ok, _} =
      purchase_fixture(user, release, %{price_cents: 6_990, store_credit_used_cents: 2_000})

    money = Planner.summary(user).money
    assert money.committed_cents == 6_990
    assert money.out_of_pocket_cents == 4_990
  end

  test "calendar excludes vetoed releases and labels availability", %{user: user} do
    exclusive = game_fixture(%{title: "Exclusive"})
    multi = game_fixture(%{title: "Multi", availability: :multiplatform})

    {:ok, r1} =
      Catalog.create_release(exclusive.id, %{platform: :switch, release_date: ~D[2026-12-01]})

    {:ok, _r2} =
      Catalog.create_release(multi.id, %{platform: :switch, release_date: ~D[2026-12-02]})

    {:ok, _} = Library.create_entry(user, %{game_id: exclusive.id, purchase_intent: :want})
    {:ok, _} = Library.create_entry(user, %{game_id: multi.id, purchase_intent: :want})
    {:ok, _} = Library.create_veto(user, %{release_id: r1.id, reason: "PC"})
    calendar = Planner.upcoming_releases(user, ~D[2026-01-01])
    assert Enum.map(calendar, & &1.recommendation) == ["can_wait"]
  end

  test "usage signal combines stalled time and completed run history" do
    game = %Game{estimated_duration_minutes: 90, pace: :normal}
    entry = %Entry{backlog: :backlog, play_state: :paused}

    events = [
      %Event{type: :added, occurred_at: ~U[2026-01-01 00:00:00Z]},
      %Event{type: :started, occurred_at: ~U[2026-01-03 00:00:00Z]},
      %Event{type: :paused, occurred_at: ~U[2026-01-05 00:00:00Z]},
      %Event{type: :resumed, occurred_at: ~U[2026-01-06 00:00:00Z]},
      %Event{type: :finished, occurred_at: ~U[2026-01-10 00:00:00Z]}
    ]

    signal = Planner.usage_signal(entry, game, events, ~U[2026-01-15 00:00:00Z])

    assert signal.stalled_days == 10
    assert signal.state_changes == 4
    assert signal.completed_runs == 1
    assert signal.typical_completion_days == 7
    assert signal.duration_minutes == 90
    assert signal.pace == :normal
    assert signal.confidence == :observed
  end

  test "usage signal is honest when the log has no usable history" do
    signal =
      Planner.usage_signal(
        %Entry{backlog: :backlog, play_state: :unplayed},
        %Game{},
        [],
        ~U[2026-01-15 00:00:00Z]
      )

    assert signal.confidence == :insufficient
    assert signal.stalled_since == nil
    assert signal.stalled_days == nil
    assert signal.typical_completion_days == nil
  end

  test "state transition events keep the game association", %{user: user} do
    game = game_fixture()
    {:ok, entry} = Library.create_entry(user, %{game_id: game.id})
    {:ok, _entry} = Library.update_entry(user, entry, %{play_state: :playing})

    assert %{game_id: game_id, type: :started} =
             Enum.find(Dockd.Activity.list_events(user), &(&1.type == :started))

    assert game_id == game.id
  end

  test "backlog excludes unowned wishes but includes owned unplayed games", %{user: user} do
    owned_game = game_fixture(%{title: "Owned unplayed"})
    wish = game_fixture(%{title: "Unowned wish"})
    release = release_fixture(owned_game)

    {:ok, _ownership} =
      Library.create_ownership(user, %{
        release_id: release.id,
        ownership_type: :digital,
        acquired_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, _} = Library.create_entry(user, %{game_id: owned_game.id})
    {:ok, _} = Library.create_entry(user, %{game_id: wish.id, purchase_intent: :want})

    assert Enum.map(Planner.backlog(user, ~U[2026-01-15 00:00:00Z]), & &1.game.title) == [
             "Owned unplayed"
           ]
  end

  test "backlog is ordered by oldest event", %{user: user} do
    old = game_fixture(%{title: "Old"})
    new = game_fixture(%{title: "New"})
    {:ok, _} = Library.create_entry(user, %{game_id: old.id, backlog: :backlog})
    {:ok, _} = Library.create_entry(user, %{game_id: new.id, backlog: :backlog})
    assert Enum.map(Planner.backlog(user), & &1.game.title) == ["Old", "New"]
  end
end
