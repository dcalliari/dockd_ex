defmodule DockdWeb.WalletLive do
  use DockdWeb, :live_view
  alias Dockd.Accounts
  alias Dockd.Wallet
  alias Dockd.Wallet.{BalanceReservation, StoreBalance}

  @impl true
  def mount(_params, _session, socket) do
    owner = Accounts.default_owner()
    {:ok, refresh(socket, owner)}
  end

  @impl true
  def handle_event("save-balance", %{"balance" => attrs}, socket) do
    attrs = normalize_money(attrs, "amount_cents")

    result =
      case Wallet.get_balance(socket.assigns.owner, :eshop) do
        nil -> Wallet.create_balance(socket.assigns.owner, atomize(attrs))
        balance -> Wallet.update_balance(socket.assigns.owner, balance, atomize(attrs))
      end

    case result do
      {:ok, _} ->
        {:noreply, refresh(socket, socket.assigns.owner) |> put_flash(:info, "Saldo salvo.")}

      {:error, changeset} ->
        {:noreply, assign(socket, balance_form: to_form(changeset))}
    end
  end

  def handle_event("new-reservation", _, socket),
    do:
      {:noreply,
       assign(socket, reservation_form: to_form(Ecto.Changeset.change(%BalanceReservation{})))}

  def handle_event("edit-reservation", %{"id" => id}, socket) do
    reservation = Wallet.get_reservation!(socket.assigns.owner, id)
    {:noreply, assign(socket, reservation_form: to_form(Ecto.Changeset.change(reservation)))}
  end

  def handle_event("save-reservation", %{"reservation" => attrs}, socket) do
    attrs = normalize_money(attrs, "amount_cents")
    attrs = atomize(attrs) |> Map.put(:store, :eshop)

    result =
      case Map.get(attrs, :id) do
        nil ->
          Wallet.create_reservation(socket.assigns.owner, attrs)

        "" ->
          Wallet.create_reservation(socket.assigns.owner, attrs)

        id ->
          Wallet.update_reservation(
            socket.assigns.owner,
            Wallet.get_reservation!(socket.assigns.owner, id),
            attrs
          )
      end

    case result do
      {:ok, _} ->
        {:noreply, refresh(socket, socket.assigns.owner) |> put_flash(:info, "Reserva criada.")}

      {:error, changeset} ->
        {:noreply, assign(socket, reservation_form: to_form(changeset))}
    end
  end

  def handle_event("delete-reservation", %{"id" => id}, socket) do
    reservation = Wallet.get_reservation!(socket.assigns.owner, id)
    {:ok, _} = Wallet.delete_reservation(socket.assigns.owner, reservation)
    {:noreply, refresh(socket, socket.assigns.owner)}
  end

  defp refresh(socket, owner) do
    balance = Wallet.get_balance(owner, :eshop) || %StoreBalance{store: :eshop, currency: "BRL"}

    assign(socket,
      owner: owner,
      balance: balance,
      reservations: Wallet.list_reservations(owner),
      balance_form: to_form(Ecto.Changeset.change(balance)),
      reservation_form: to_form(Ecto.Changeset.change(%BalanceReservation{}))
    )
  end

  defp normalize_money(attrs, key) do
    case DockdWeb.DockdComponents.parse_money(Map.get(attrs, key)) do
      {:ok, nil} -> Map.put(attrs, key, nil)
      {:ok, cents} -> Map.put(attrs, key, cents)
      :error -> attrs
    end
  end

  defp atomize(attrs),
    do: Map.new(attrs, fn {key, value} -> {String.to_existing_atom(key), value} end)
end
