defmodule Dockd.Purchasing do
  @moduledoc "User-scoped purchases and dated price observations."
  import Ecto.Query
  import Ecto.Changeset
  alias Dockd.Accounts.User
  alias Dockd.Activity
  alias Dockd.Catalog.Release
  alias Dockd.Library
  alias Dockd.Library.Entry
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
    |> Ecto.Multi.run(:purchased_event, fn repo, %{release: release} ->
      insert_event(repo, %{
        user_id: user_id,
        game_id: release.game_id,
        release_id: release.id,
        type: :purchased,
        occurred_at: DateTime.utc_now(),
        payload: Map.put(attrs, :game_id, release.game_id)
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
    |> Ecto.Multi.run(:entry, fn repo, %{release: release} ->
      close_entry_after_purchase(repo, user_id, release.game_id)
    end)
    |> Ecto.Multi.run(:balance, fn repo, %{purchase: purchase} ->
      debit_credit(repo, user_id, purchase)
    end)
    |> Ecto.Multi.run(:reservation, fn repo, %{release: release} ->
      consume_reservations(repo, user_id, release.game_id)
    end)
    |> Repo.transaction()
    |> result(:purchase)
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
      :store_credit_used_cents,
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
        :store_credit_used_cents,
        :purchased_at,
        :is_preorder,
        :retailer
      ])
      |> validate_required([
        :user_id,
        :release_id,
        :format,
        :price_cents,
        :purchased_at,
        :retailer
      ])
      |> assoc_constraint(:release)
      |> validate_number(:price_cents, greater_than_or_equal_to: 0)
      |> validate_number(:store_credit_used_cents, greater_than_or_equal_to: 0)

  defp price_changeset(s, a),
    do:
      s
      |> cast(a, [:user_id, :release_id, :format, :price_cents, :currency, :observed_at, :source])
      |> validate_required([:user_id, :release_id, :format, :price_cents, :observed_at, :source])
      |> validate_number(:price_cents, greater_than_or_equal_to: 0)

  defp result({:ok, values}, key), do: {:ok, values[key]}
  defp result({:error, _, changeset, _}, _), do: {:error, changeset}

  defp insert_event(repo, attrs), do: repo.insert(Activity.changeset(%Activity.Event{}, attrs))

  defp close_entry_after_purchase(repo, user_id, game_id) do
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
             {:ok, _} <- insert_transition_events(repo, user_id, game_id, entry, updated) do
          {:ok, updated}
        end
    end
  end

  defp insert_transition_events(repo, user_id, game_id, before, after_state) do
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
        payload: %{field: field, from: old, to: new}
      }

      case insert_event(repo, attrs) do
        {:ok, event} -> {:cont, {:ok, event}}
        error -> {:halt, error}
      end
    end)
  end

  defp debit_credit(_repo, _user_id, %Purchase{store_credit_used_cents: 0}), do: {:ok, nil}

  defp debit_credit(repo, user_id, %Purchase{} = purchase) do
    balance =
      repo.one(
        from b in Dockd.Wallet.StoreBalance,
          where: b.user_id == ^user_id and b.store == :eshop and b.currency == ^purchase.currency,
          lock: "FOR UPDATE"
      )

    cond do
      is_nil(balance) ->
        {:error, credit_error("não há saldo eShop na moeda da compra")}

      balance.amount_cents < purchase.store_credit_used_cents ->
        {:error, credit_error("saldo eShop insuficiente para o crédito informado")}

      true ->
        balance
        |> Ecto.Changeset.change(
          amount_cents: balance.amount_cents - purchase.store_credit_used_cents
        )
        |> repo.update()
    end
  end

  defp credit_error(message),
    do:
      Ecto.Changeset.add_error(
        %Ecto.Changeset{data: %Purchase{}, changes: %{}, errors: [], valid?: false},
        :store_credit_used_cents,
        message
      )

  defp consume_reservations(repo, user_id, game_id) do
    {count, _} =
      repo.delete_all(
        from r in Dockd.Wallet.BalanceReservation,
          where: r.user_id == ^user_id and r.game_id == ^game_id and r.store == :eshop
      )

    {:ok, count}
  end
end
