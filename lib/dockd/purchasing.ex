defmodule Dockd.Purchasing do
  @moduledoc "User-scoped purchases and dated price observations."
  import Ecto.Query
  import Ecto.Changeset
  alias Dockd.Accounts.User
  alias Dockd.Activity
  alias Dockd.Catalog.Release
  alias Dockd.Library
  alias Dockd.Library.Entry
  alias Dockd.Library.Ownership
  alias Dockd.Purchasing.PriceObservation
  alias Dockd.Purchasing.Purchase
  alias Dockd.Repo
  @default_stale_age_days 7
  @doc "Lists purchases for a user."
  def list_purchases(%User{id: id}),
    do:
      Repo.all(
        from p in Purchase,
          where: p.user_id == ^id,
          order_by: [desc: p.purchased_at],
          preload: [:release]
      )

  @doc "Updates a purchase scoped to a user."
  def update_purchase(%User{id: id}, %Purchase{} = purchase, attrs),
    do:
      if(purchase.user_id == id,
        do: purchase |> purchase_changeset(attrs) |> Repo.update(),
        else: {:error, :not_found}
      )

  @doc "Deletes a purchase scoped to a user."
  def delete_purchase(%User{id: id}, %Purchase{} = purchase),
    do: if(purchase.user_id == id, do: Repo.delete(purchase), else: {:error, :not_found})

  @doc "Creates a purchase and its event atomically."
  def create_purchase(%User{id: user_id}, attrs) do
    attrs = normalize_attrs(attrs)

    purchase_changeset =
      purchase_changeset(%Purchase{user_id: user_id}, Map.put(attrs, :user_id, user_id))

    Ecto.Multi.new()
    |> Ecto.Multi.run(:release, fn repo, _ ->
      case repo.get(Release, attrs[:release_id]) do
        nil ->
          {:error, Ecto.Changeset.add_error(purchase_changeset, :release_id, "não encontrado")}

        release ->
          {:ok, release}
      end
    end)
    |> Ecto.Multi.insert(:purchase, purchase_changeset)
    |> Ecto.Multi.run(:purchased_event, fn repo, %{release: release, purchase: purchase} ->
      insert_event(repo, %{
        user_id: user_id,
        game_id: release.game_id,
        release_id: release.id,
        type: :purchased,
        occurred_at: DateTime.utc_now(),
        payload: attrs |> Map.put(:game_id, release.game_id) |> Map.put(:purchase_id, purchase.id)
      })
    end)
    |> Ecto.Multi.run(:ownership, fn repo, %{purchase: purchase} ->
      Library.insert_ownership(repo, %User{id: user_id}, %{
        release_id: attrs[:release_id],
        ownership_type: attrs[:format],
        acquired_at: attrs[:purchased_at],
        purchase_id: purchase.id
      })
    end)
    |> Ecto.Multi.run(:entry, fn repo, %{release: release, purchase: purchase} ->
      close_entry_after_purchase(repo, user_id, release.game_id, purchase.id)
    end)
    |> Repo.transaction()
    |> result(:purchase)
  end

  @doc """
  Undoes a purchase recorded by mistake, as if it never happened: the purchase, the
  ownership it created and the events it wrote go away, and the entry gets back the intent
  the purchase closed.
  """
  def undo_purchase(%User{id: user_id}, %Purchase{user_id: user_id} = purchase) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:events, fn repo, _ ->
      {:ok,
       repo.all(
         from e in Activity.Event,
           where:
             e.user_id == ^user_id and
               fragment("?->>'purchase_id'", e.payload) == ^purchase.id
       )}
    end)
    |> Ecto.Multi.run(:entry, fn repo, %{events: events} ->
      reopen_entry(repo, user_id, events)
    end)
    |> Ecto.Multi.run(:deleted_events, fn repo, %{events: events} ->
      ids = Enum.map(events, & &1.id)
      {count, _} = repo.delete_all(from e in Activity.Event, where: e.id in ^ids)
      {:ok, count}
    end)
    |> Ecto.Multi.delete_all(
      :ownerships,
      from(o in Ownership, where: o.user_id == ^user_id and o.purchase_id == ^purchase.id)
    )
    |> Ecto.Multi.delete(:purchase, purchase)
    |> Repo.transaction()
    |> result(:purchase)
  end

  def undo_purchase(%User{}, %Purchase{}), do: {:error, :not_found}

  @doc "Sum of what the user paid for purchases in the month of `today`."
  def month_spending(%User{id: id}, today \\ Date.utc_today()) do
    first = today |> Date.beginning_of_month() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    next = today |> Date.end_of_month() |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    Repo.one(
      from p in Purchase,
        where: p.user_id == ^id and p.purchased_at >= ^first and p.purchased_at < ^next,
        select: coalesce(sum(p.price_cents), 0)
    )
  end

  @doc """
  The price a screen shows for a release, optionally of one media. Every screen reads
  prices here and only here: today it is the user's latest observation, and the store
  price takes its place later without touching the screens.
  """
  def current_price(user, release_id, format \\ nil)

  def current_price(%User{} = user, release_id, nil),
    do: latest_price_observation(user, release_id)

  def current_price(%User{id: id}, release_id, format),
    do:
      Repo.one(
        from p in PriceObservation,
          where: p.user_id == ^id and p.release_id == ^release_id and p.format == ^format,
          order_by: [desc: p.observed_at],
          limit: 1
      )

  @doc "The most recent `current_price/3` among a game's releases, optionally of one media."
  def current_game_price(%User{} = user, releases, format \\ nil) do
    releases
    |> Enum.map(&current_price(user, &1.id, format))
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(& &1.observed_at, DateTime, fn -> nil end)
  end

  @doc "Gets a purchase scoped to a user."
  def get_purchase!(%User{id: id}, purchase_id),
    do: Repo.one!(from p in Purchase, where: p.id == ^purchase_id and p.user_id == ^id)

  @doc "Lists price observations for a user and release."
  def list_price_observations(%User{id: id}, release_id),
    do:
      Repo.all(
        from p in PriceObservation,
          where: p.user_id == ^id and p.release_id == ^release_id,
          order_by: [desc: p.observed_at]
      )

  @doc "Gets a price observation scoped to a user."
  def get_price_observation!(%User{id: id}, observation_id),
    do: Repo.one!(from p in PriceObservation, where: p.id == ^observation_id and p.user_id == ^id)

  @doc "Updates a price observation scoped to a user."
  def update_price_observation(
        %User{id: id},
        %PriceObservation{} = observation,
        attrs
      ),
      do:
        if(observation.user_id == id,
          do: observation |> price_changeset(attrs) |> Repo.update(),
          else: {:error, :not_found}
        )

  @doc "Deletes a price observation scoped to a user."
  def delete_price_observation(%User{id: id}, %PriceObservation{} = observation),
    do: if(observation.user_id == id, do: Repo.delete(observation), else: {:error, :not_found})

  @doc "Creates a dated price observation."
  def create_price_observation(%User{id: id}, attrs) do
    attrs = normalize_attrs(attrs)

    %PriceObservation{user_id: id}
    |> price_changeset(Map.put(attrs, :user_id, id))
    |> Repo.insert()
  end

  @doc "Returns whether an observation is older than the threshold, defaulting to seven days."
  def stale?(
        %PriceObservation{observed_at: observed_at},
        now,
        age_days \\ @default_stale_age_days
      ),
      do: DateTime.diff(now, observed_at, :second) > age_days * 86_400

  @doc "Returns the latest observation for a user and release."
  def latest_price_observation(%User{id: id}, release_id),
    do:
      Repo.one(
        from p in PriceObservation,
          where: p.user_id == ^id and p.release_id == ^release_id,
          order_by: [desc: p.observed_at],
          limit: 1
      )

  @doc "Lists purchases for a user and game."
  def list_purchases_for_game(%User{id: id}, game_id),
    do:
      Repo.all(
        from p in Purchase,
          join: r in Release,
          on: r.id == p.release_id,
          where: p.user_id == ^id and r.game_id == ^game_id,
          order_by: [desc: p.purchased_at]
      )

  @doc "Returns purchases for a user and release."
  def list_purchases(%User{id: id}, release_id),
    do:
      Repo.all(
        from p in Purchase,
          where: p.user_id == ^id and p.release_id == ^release_id,
          order_by: [desc: p.purchased_at]
      )

  defp normalize_attrs(attrs) do
    keys = [
      :release_id,
      :format,
      :price_cents,
      :currency,
      :purchased_at,
      :is_preorder,
      :retailer,
      :observed_at,
      :source
    ]

    Enum.reduce(keys, %{}, fn key, result ->
      value = Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
      if is_nil(value), do: result, else: Map.put(result, key, value)
    end)
  end

  defp purchase_changeset(s, a),
    do:
      s
      |> cast(a, [
        :user_id,
        :release_id,
        :format,
        :price_cents,
        :currency,
        :purchased_at,
        :is_preorder,
        :retailer
      ])
      |> validate_required([:user_id, :release_id, :format, :purchased_at])
      |> assoc_constraint(:release)
      |> validate_number(:price_cents, greater_than_or_equal_to: 0)

  defp price_changeset(s, a),
    do:
      s
      |> cast(a, [:user_id, :release_id, :format, :price_cents, :currency, :observed_at, :source])
      |> validate_required([:user_id, :release_id, :format, :price_cents, :observed_at, :source])
      |> validate_number(:price_cents, greater_than_or_equal_to: 0)

  defp result({:ok, values}, key), do: {:ok, values[key]}
  defp result({:error, _, changeset, _}, _), do: {:error, changeset}

  defp insert_event(repo, attrs), do: repo.insert(Activity.changeset(%Activity.Event{}, attrs))

  defp close_entry_after_purchase(repo, user_id, game_id, purchase_id) do
    case repo.one(
           from e in Entry,
             where: e.user_id == ^user_id and e.game_id == ^game_id,
             lock: "FOR UPDATE"
         ) do
      nil ->
        {:ok, nil}

      entry ->
        purchase_intent =
          if entry.purchase_intent in [:want, :planned, :preordered],
            do: :none,
            else: entry.purchase_intent

        attrs = %{
          purchase_intent: purchase_intent,
          backlog: if(entry.backlog == :no, do: :backlog, else: entry.backlog)
        }

        changeset = Entry.changeset(entry, attrs)

        with {:ok, updated} <- repo.update(changeset),
             {:ok, _} <-
               insert_transition_events(repo, user_id, game_id, entry, updated, purchase_id) do
          {:ok, updated}
        end
    end
  end

  defp insert_transition_events(repo, user_id, game_id, before, after_state, purchase_id) do
    events =
      [
        {:purchase_intent, before.purchase_intent, after_state.purchase_intent},
        {:backlog, before.backlog, after_state.backlog}
      ]
      |> Enum.filter(fn {_, old, new} -> old != new end)

    Enum.reduce_while(events, {:ok, nil}, fn {field, old, new}, _acc ->
      type = if field == :purchase_intent, do: :intent_changed, else: :backlogged

      attrs = %{
        user_id: user_id,
        game_id: game_id,
        type: type,
        occurred_at: DateTime.utc_now(),
        payload: %{field: field, from: old, to: new, purchase_id: purchase_id}
      }

      case insert_event(repo, attrs) do
        {:ok, event} -> {:cont, {:ok, event}}
        error -> {:halt, error}
      end
    end)
  end

  # The entry fields the undone purchase changed, back to their `from` values, without new
  # events: the purchase never happened.
  defp reopen_entry(repo, user_id, events) do
    changes =
      for %{type: type, payload: %{"field" => field, "from" => from}} <- events,
          type in [:intent_changed, :backlogged],
          into: %{},
          do: {field, from}

    case {changes, events |> Enum.map(& &1.game_id) |> Enum.find(& &1)} do
      {empty, _} when map_size(empty) == 0 ->
        {:ok, nil}

      {changes, game_id} ->
        case repo.one(from e in Entry, where: e.user_id == ^user_id and e.game_id == ^game_id) do
          nil -> {:ok, nil}
          entry -> entry |> Entry.changeset(changes) |> repo.update()
        end
    end
  end
end
