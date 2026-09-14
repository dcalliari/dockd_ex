defmodule Dockd.Planner do
  @moduledoc "Read-only purchase planner queries."
  import Ecto.Query
  alias Dockd.Accounts.User
  alias Dockd.Activity.Event
  alias Dockd.Catalog.{Game, Release}
  alias Dockd.Library.{Entry, ReleaseVeto}
  alias Dockd.Purchasing.Purchase
  alias Dockd.Repo
  alias Dockd.Wallet.{BalanceReservation, StoreBalance}

  @doc "Builds the home summary for the default user's current state."
  def summary(%User{id: user_id}, today \\ Date.utc_today()) do
    balances = Repo.all(from b in StoreBalance, where: b.user_id == ^user_id)
    reservations = Repo.all(from r in BalanceReservation, where: r.user_id == ^user_id)
    purchases = Repo.all(from p in Purchase, where: p.user_id == ^user_id)
    currency = (List.first(balances) || %{currency: "BRL"}).currency
    amount = Enum.reduce(balances, 0, &(&1.amount_cents + &2))
    reserved = Enum.reduce(reservations, 0, &(&1.amount_cents + &2))
    committed = Enum.reduce(purchases, 0, &(&1.price_cents + &2.store_credit_used_cents))
    month_start = Date.beginning_of_month(today)

    spent_month =
      purchases
      |> Enum.filter(
        &(Date.compare(DateTime.to_date(&1.purchased_at), month_start) in [:eq, :gt])
      )
      |> Enum.reduce(0, &(&1.price_cents + &2.store_credit_used_cents))

    %{
      money: %{
        balance_cents: amount,
        reserved_cents: reserved,
        free_cents: amount - reserved,
        committed_cents: committed,
        spent_month_cents: spent_month,
        currency: currency
      },
      calendar: upcoming_releases(%User{id: user_id}, today),
      backlog: backlog(%User{id: user_id})
    }
  end

  @doc "Lists wanted releases, excluding vetoed versions."
  def upcoming_releases(%User{id: user_id}, today \\ Date.utc_today()) do
    vetoed = from v in ReleaseVeto, where: v.user_id == ^user_id, select: v.release_id

    Repo.all(
      from r in Release,
        join: g in Game,
        on: g.id == r.game_id,
        join: e in Entry,
        on: e.game_id == g.id and e.user_id == ^user_id,
        where:
          not is_nil(r.release_date) and r.release_date >= ^today and
            e.purchase_intent in [:want, :planned, :preordered] and r.id not in subquery(vetoed),
        order_by: r.release_date,
        select: %{
          release: r,
          game: g,
          recommendation:
            fragment(
              "CASE WHEN ? = 'multiplatform' THEN 'can_wait' ELSE 'reserve' END",
              g.availability
            )
        }
    )
  end

  @doc "Reports owned unplayed and backlog entries with their oldest event date."
  def backlog(%User{id: user_id}) do
    entries =
      Repo.all(
        from e in Entry,
          join: g in Game,
          on: g.id == e.game_id,
          where:
            e.user_id == ^user_id and
              (e.backlog in [:backlog, :active] or e.play_state == :unplayed),
          select: %{entry: e, game: g}
      )

    Enum.map(entries, fn item ->
      Map.put(
        item,
        :oldest_at,
        Repo.one(
          from event in Event,
            where:
              event.user_id == ^user_id and event.game_id == ^item.game.id and
                event.type in [:backlogged, :added],
            order_by: [asc: event.occurred_at],
            limit: 1,
            select: event.occurred_at
        )
      )
    end)
  end
end
