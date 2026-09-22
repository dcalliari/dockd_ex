defmodule Dockd.Planner do
  @moduledoc "Read-only purchase planner queries and usage-based recommendations."
  import Ecto.Query
  alias Dockd.Accounts.User
  alias Dockd.Activity.Event
  alias Dockd.Catalog.{Game, Release}
  alias Dockd.Library
  alias Dockd.Library.{Entry, ReleaseVeto}
  alias Dockd.Purchasing
  alias Dockd.Purchasing.Purchase
  alias Dockd.Repo
  alias Dockd.Wallet.{BalanceReservation, StoreBalance}

  @state_event_types [:started, :paused, :resumed, :finished, :abandoned, :backlogged, :activated]

  @doc "Builds the home summary for the default user's current state."
  def summary(%User{id: user_id}, today \\ Date.utc_today()) do
    balances = Repo.all(from b in StoreBalance, where: b.user_id == ^user_id)
    reservations = Repo.all(from r in BalanceReservation, where: r.user_id == ^user_id)
    purchases = Repo.all(from p in Purchase, where: p.user_id == ^user_id)
    currency = (List.first(balances) || %{currency: "BRL"}).currency
    amount = Enum.reduce(balances, 0, &(&1.amount_cents + &2))
    reserved = Enum.reduce(reservations, 0, &(&1.amount_cents + &2))

    committed = Enum.reduce(purchases, 0, &(&1.price_cents + &2))

    out_of_pocket =
      Enum.reduce(purchases, 0, fn purchase, total ->
        total + purchase.price_cents - (purchase.store_credit_used_cents || 0)
      end)

    month_start = Date.beginning_of_month(today)

    spent_month =
      purchases
      |> Enum.filter(
        &(Date.compare(DateTime.to_date(&1.purchased_at), month_start) in [:eq, :gt])
      )
      |> Enum.reduce(0, &(&1.price_cents + &2))

    money = %{
      balance_cents: amount,
      reserved_cents: reserved,
      free_cents: amount - reserved,
      committed_cents: committed,
      out_of_pocket_cents: out_of_pocket,
      spent_month_cents: spent_month,
      currency: currency
    }

    calendar = upcoming_releases(%User{id: user_id}, today)
    backlog = backlog(%User{id: user_id})

    %{
      money: money,
      calendar: calendar,
      calendar_empty_reason: calendar_empty_reason(%User{id: user_id}, calendar, today),
      opportunities: purchase_opportunities(%User{id: user_id}, today, money),
      backlog: backlog,
      recommendation: recommendation_summary(List.first(backlog))
    }
  end

  @doc "Lists wanted releases, excluding vetoed versions."
  def upcoming_releases(%User{id: user_id}, today \\ Date.utc_today()) do
    vetoed = from v in ReleaseVeto, where: v.user_id == ^user_id, select: v.release_id

    reservations =
      Repo.all(
        from r in BalanceReservation,
          where: r.user_id == ^user_id,
          group_by: r.game_id,
          select: {r.game_id, sum(r.amount_cents)}
      )
      |> Map.new()

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
    |> Enum.map(&Map.put(&1, :reserved_cents, Map.get(reservations, &1.game.id, 0)))
  end

  @doc "Lists launched or undated desires with a dated price verdict."
  def purchase_opportunities(%User{id: user_id}, today \\ Date.utc_today(), money \\ nil) do
    money = money || summary_money(%User{id: user_id})

    releases =
      Repo.all(
        from r in Release,
          join: g in Game,
          on: g.id == r.game_id,
          join: e in Entry,
          on: e.game_id == g.id and e.user_id == ^user_id,
          where:
            e.purchase_intent in [:want, :planned, :preordered] and
              (is_nil(r.release_date) or r.release_date < ^today),
          order_by: [asc: r.release_date, asc: g.title],
          select: %{release: r, game: g, entry: e}
      )

    releases
    |> Enum.map(fn item ->
      observation = Purchasing.latest_price_observation(%User{id: user_id}, item.release.id)
      verdict = purchase_verdict(item.entry, observation, money)

      item
      |> Map.put(:observation, observation)
      |> Map.put(:verdict, verdict.verdict)
      |> Map.put(:verdict_label, verdict.label)
      |> Map.put(:verdict_reason, verdict.reason)
      |> Map.put(
        :observation_stale?,
        observation && Purchasing.stale?(observation, DateTime.utc_now())
      )
    end)
  end

  @doc "Formats a release date without pretending an IGDB year-only date is exact."
  def release_date_label(nil), do: "Data não informada"
  def release_date_label(%Date{month: 12, day: 31, year: year}), do: "#{year}, a definir"
  def release_date_label(%Date{} = date), do: Calendar.strftime(date, "%d/%m/%Y")

  defp summary_money(%User{id: user_id}) do
    balances = Repo.all(from b in StoreBalance, where: b.user_id == ^user_id)
    reservations = Repo.all(from r in BalanceReservation, where: r.user_id == ^user_id)
    currency = (List.first(balances) || %{currency: "BRL"}).currency

    %{
      free_cents:
        Enum.reduce(balances, 0, &(&1.amount_cents + &2)) -
          Enum.reduce(reservations, 0, &(&1.amount_cents + &2)),
      currency: currency
    }
  end

  defp purchase_verdict(_entry, nil, _money),
    do: %{verdict: :record_price, label: "Registrar preço", reason: "Sem observação de preço."}

  defp purchase_verdict(entry, observation, wallet) when is_struct(observation) do
    stale? = Purchasing.stale?(observation, DateTime.utc_now())

    if stale? do
      %{
        verdict: :record_price,
        label: "Atualizar preço",
        reason: "A última observação está desatualizada; confirme o valor antes de decidir."
      }
    else
      purchase_verdict_with_observation(observation, entry, wallet)
    end
  end

  defp purchase_verdict_with_observation(observation, entry, wallet) do
    cond do
      is_nil(entry.target_price_cents) ->
        %{
          verdict: :record_price,
          label: "Definir alvo",
          reason: "Registre um preço alvo para comparar."
        }

      observation.price_cents > entry.target_price_cents ->
        %{
          verdict: :wait,
          label: "Esperar",
          reason: "A observação está acima do alvo de preço registrado."
        }

      observation.price_cents > wallet.free_cents ->
        %{
          verdict: :wait,
          label: "Esperar",
          reason: "Está abaixo do alvo, mas não cabe no saldo livre disponível."
        }

      true ->
        %{
          verdict: :buy,
          label: "Comprar agora",
          reason: "A observação está abaixo do alvo e cabe no livre."
        }
    end
  end

  defp calendar_empty_reason(%User{id: user_id}, [], _today) do
    undated_count =
      Repo.one(
        from e in Entry,
          join: r in Release,
          on: r.game_id == e.game_id,
          where:
            e.user_id == ^user_id and e.purchase_intent in [:want, :planned, :preordered] and
              is_nil(r.release_date),
          select: count(r.id)
      )

    if undated_count > 0,
      do: "Seus desejos têm versões sem data de lançamento.",
      else: "Nenhum lançamento futuro para os desejos atuais."
  end

  defp calendar_empty_reason(_user, _calendar, _today), do: nil

  @doc "Reports backlog entries ordered by a usage signal, not only by insertion date."
  def backlog(%User{id: user_id}, now \\ DateTime.utc_now()) do
    owned_game_ids = Library.owned_game_ids(%User{id: user_id})

    entries =
      Repo.all(
        from e in Entry,
          join: g in Game,
          on: g.id == e.game_id,
          where:
            e.user_id == ^user_id and
              (e.backlog in [:backlog, :active] or
                 (e.play_state == :unplayed and e.game_id in ^owned_game_ids)),
          select: %{entry: e, game: g}
      )

    game_ids = Enum.map(entries, & &1.game.id)

    events_by_game =
      Repo.all(
        from event in Event,
          where: event.user_id == ^user_id and event.game_id in ^game_ids,
          order_by: [asc: event.occurred_at]
      )
      |> Enum.group_by(& &1.game_id)

    entries
    |> Enum.map(fn item ->
      events = Map.get(events_by_game, item.game.id, [])
      signal = usage_signal(item.entry, item.game, events, now)

      item
      |> Map.put(:oldest_at, oldest_at(events))
      |> Map.put(:usage_signal, signal)
      |> Map.put(:recommendation, recommendation(item.entry, item.game, signal))
    end)
    |> Enum.sort(&backlog_item_before?/2)
  end

  @doc "Calculates temporal signals from the append-only log for one backlog entry."
  def usage_signal(%Entry{} = entry, %Game{} = game, events, now \\ DateTime.utc_now()) do
    events = Enum.sort(events, &(DateTime.compare(&1.occurred_at, &2.occurred_at) != :gt))
    stalled_since = stalled_since(entry, events)
    completion_days = completion_days(events)
    state_changes = Enum.count(events, &(&1.type in @state_event_types))

    %{
      stalled_since: stalled_since,
      stalled_days: elapsed_days(stalled_since, now),
      state_changes: state_changes,
      completed_runs: length(completion_days),
      typical_completion_days: average(completion_days),
      duration_minutes: entry.duration_override_minutes || game.estimated_duration_minutes,
      pace: entry.pace_override || game.pace,
      confidence: signal_confidence(stalled_since, completion_days, state_changes)
    }
  end

  defp recommendation(entry, game, signal) do
    %{
      score: recommendation_score(entry, signal),
      confidence: signal.confidence,
      reason:
        recommendation_reason(signal)
        |> Kernel.<>(catalog_context(entry, game))
    }
  end

  defp recommendation_summary(nil), do: nil

  defp recommendation_summary(item) do
    %{
      game: item.game,
      reason: item.recommendation.reason,
      confidence: item.recommendation.confidence
    }
  end

  defp recommendation_score(entry, signal) do
    priority_score = %{low: 0, normal: 10, high: 20}

    (signal.stalled_days || 0) +
      Map.get(priority_score, entry.priority, 10) +
      if(entry.backlog == :active, do: 15, else: 0) + min(signal.state_changes, 5)
  end

  defp backlog_item_before?(left, right) do
    left_score = left.recommendation.score
    right_score = right.recommendation.score

    cond do
      left_score > right_score -> true
      left_score < right_score -> false
      is_nil(left.oldest_at) -> false
      is_nil(right.oldest_at) -> true
      true -> DateTime.compare(left.oldest_at, right.oldest_at) != :gt
    end
  end

  defp oldest_at(events) do
    events
    |> Enum.filter(&(&1.type in [:added, :backlogged]))
    |> Enum.sort(&(DateTime.compare(&1.occurred_at, &2.occurred_at) != :gt))
    |> List.first()
    |> case do
      nil -> nil
      event -> event.occurred_at
    end
  end

  defp stalled_since(%Entry{play_state: :playing}, events),
    do: latest_event_at(events, [:started, :resumed])

  defp stalled_since(%Entry{play_state: :paused}, events),
    do: latest_event_at(events, [:paused])

  defp stalled_since(%Entry{backlog: :active}, events),
    do: latest_event_at(events, [:activated, :backlogged, :added])

  defp stalled_since(%Entry{backlog: :backlog}, events),
    do: latest_event_at(events, [:backlogged, :added])

  defp stalled_since(%Entry{play_state: :unplayed}, events),
    do: latest_event_at(events, [:added])

  defp stalled_since(_entry, _events), do: nil

  defp latest_event_at(events, types) do
    events
    |> Enum.filter(&(&1.type in types))
    |> Enum.sort(&(DateTime.compare(&1.occurred_at, &2.occurred_at) != :gt))
    |> List.last()
    |> case do
      nil -> nil
      event -> event.occurred_at
    end
  end

  defp elapsed_days(nil, _now), do: nil

  defp elapsed_days(since, now) do
    max(DateTime.diff(now, since, :second), 0) |> div(86_400)
  end

  defp completion_days(events) do
    Enum.reduce(events, {nil, []}, fn event, {started_at, durations} ->
      cond do
        event.type in [:started, :resumed] and is_nil(started_at) ->
          {event.occurred_at, durations}

        event.type == :finished and started_at ->
          days = max(DateTime.diff(event.occurred_at, started_at, :second), 0) |> div(86_400)
          {nil, [days | durations]}

        true ->
          {started_at, durations}
      end
    end)
    |> elem(1)
  end

  defp average([]), do: nil
  defp average(values), do: round(Enum.sum(values) / length(values))

  defp signal_confidence(nil, [], 0), do: :insufficient
  defp signal_confidence(_stalled_since, [], _state_changes), do: :limited
  defp signal_confidence(_stalled_since, _completion_days, _state_changes), do: :observed

  defp recommendation_reason(%{confidence: :insufficient}),
    do: "Não há eventos suficientes para estimar há quanto tempo este jogo está parado."

  defp recommendation_reason(signal) do
    stalled_reason =
      case signal.stalled_days do
        nil -> "O log não registra um marco confiável do estado atual."
        0 -> "Este jogo mudou de estado hoje."
        days -> "Está sem avanço há #{days} dias."
      end

    history_reason =
      case signal.state_changes do
        0 -> "Ainda não há histórico de mudanças para calibrar seu ritmo."
        1 -> "Há uma mudança de estado registrada, ainda pouco para calibrar seu ritmo."
        count -> "O log registra #{count} mudanças de estado."
      end

    completion_reason =
      case signal.typical_completion_days do
        nil -> "Ainda não há finais registrados para estimar seu tempo habitual."
        days -> "Seu tempo mediano registrado para terminar jogos é de #{days} dias."
      end

    Enum.join([stalled_reason, history_reason, completion_reason], " ")
  end

  defp catalog_context(
         %{duration_override_minutes: duration_override, pace_override: pace_override},
         game
       ) do
    duration = duration_override || game.estimated_duration_minutes
    pace = pace_override || game.pace

    case {duration, pace} do
      {nil, nil} -> ""
      {duration, nil} -> " Etiqueta do catálogo: #{duration} min."
      {nil, pace} -> " Etiqueta do catálogo: ritmo #{pace_label(pace)}."
      {duration, pace} -> " Etiqueta do catálogo: #{duration} min, ritmo #{pace_label(pace)}."
    end
  end

  defp pace_label(:relaxing), do: "relaxante"
  defp pace_label(:normal), do: "normal"
  defp pace_label(:demanding), do: "exigente"
  defp pace_label(_), do: nil
end
