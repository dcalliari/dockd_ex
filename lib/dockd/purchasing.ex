defmodule Dockd.Purchasing do
  @moduledoc "User-scoped purchases and dated price observations."
  import Ecto.Query
  import Ecto.Changeset
  alias Dockd.Accounts.User
  alias Dockd.Activity
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
    cs = purchase_changeset(%Purchase{user_id: user_id}, Map.put(attrs, :user_id, user_id))

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:purchase, cs)
    |> Activity.append(%{
      user_id: user_id,
      release_id: attrs[:release_id],
      type: :purchased,
      occurred_at: DateTime.utc_now(),
      payload: Map.new(attrs)
    })
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
  def create_price_observation(%User{id: id}, attrs),
    do:
      %PriceObservation{user_id: id}
      |> price_changeset(Map.put(attrs, :user_id, id))
      |> Repo.insert()

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

  @doc "Returns purchases for a user and release."
  def list_purchases(%User{id: id}, release_id),
    do:
      Repo.all(
        from p in Purchase,
          where: p.user_id == ^id and p.release_id == ^release_id,
          order_by: [desc: p.purchased_at]
      )

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
end
