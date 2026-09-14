defmodule Dockd.Wallet do
  @moduledoc "Store balances and purchase reservations."
  import Ecto.Query
  import Ecto.Changeset
  alias Dockd.Accounts.User
  alias Dockd.Repo
  alias Dockd.Wallet.BalanceReservation
  alias Dockd.Wallet.StoreBalance
  @doc "Lists store balances for a user."
  def list_balances(%User{id: id}), do: Repo.all(from b in StoreBalance, where: b.user_id == ^id)
  @doc "Gets a user's balance for a store."
  def get_balance(%User{id: id}, store),
    do: Repo.one(from b in StoreBalance, where: b.user_id == ^id and b.store == ^store)

  @doc "Creates a store balance."
  def create_balance(%User{id: id}, attrs),
    do:
      %StoreBalance{user_id: id}
      |> balance_changeset(Map.put(attrs, :user_id, id))
      |> Repo.insert()

  @doc "Updates a store balance scoped to a user."
  def update_balance(%User{id: id}, %StoreBalance{} = balance, attrs),
    do:
      if(balance.user_id == id,
        do: balance |> balance_changeset(attrs) |> Repo.update(),
        else: {:error, :not_found}
      )

  @doc "Lists reservations for a user."
  def list_reservations(%User{id: id}),
    do: Repo.all(from r in BalanceReservation, where: r.user_id == ^id, preload: [:game])

  @doc "Creates a balance reservation."
  def create_reservation(%User{id: id}, attrs),
    do:
      %BalanceReservation{user_id: id}
      |> reservation_changeset(Map.put(attrs, :user_id, id))
      |> Repo.insert()

  @doc "Updates a reservation scoped to a user."
  def update_reservation(%User{id: id}, %BalanceReservation{} = reservation, attrs),
    do:
      if(reservation.user_id == id,
        do: reservation |> reservation_changeset(attrs) |> Repo.update(),
        else: {:error, :not_found}
      )

  @doc "Deletes a reservation scoped to a user."
  def delete_reservation(%User{id: id}, %BalanceReservation{} = reservation),
    do: if(reservation.user_id == id, do: Repo.delete(reservation), else: {:error, :not_found})

  defp balance_changeset(s, a),
    do:
      s
      |> cast(a, [:user_id, :store, :amount_cents, :currency])
      |> validate_required([:user_id, :store, :amount_cents])
      |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
      |> unique_constraint([:user_id, :store])

  defp reservation_changeset(s, a),
    do:
      s
      |> cast(a, [:user_id, :store, :game_id, :amount_cents, :note])
      |> validate_required([:user_id, :store, :game_id, :amount_cents])
      |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
      |> assoc_constraint(:game)
end
