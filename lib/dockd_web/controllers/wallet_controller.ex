defmodule DockdWeb.WalletController do
  use DockdWeb, :controller
  use OpenApiSpex.ControllerSpecs
  alias Dockd.Accounts
  alias Dockd.Wallet

  operation(:balances,
    summary: "List balances",
    responses: %{200 => {"Balances", "application/json", DockdWeb.ApiSchemas.Error}}
  )

  operation(:create_balance,
    summary: "Create balance",
    responses: %{201 => {"Balance", "application/json", DockdWeb.ApiSchemas.Error}}
  )

  operation(:reservations,
    summary: "List reservations",
    responses: %{200 => {"Reservations", "application/json", DockdWeb.ApiSchemas.Error}}
  )

  operation(:create_reservation,
    summary: "Create reservation",
    responses: %{201 => {"Reservation", "application/json", DockdWeb.ApiSchemas.Error}}
  )

  operation(:update_balance,
    summary: "Update balance",
    responses: %{200 => {"Balance", "application/json", DockdWeb.ApiSchemas.Error}}
  )

  operation(:delete_balance,
    summary: "Delete balance",
    responses: %{204 => {nil, "application/json", nil}}
  )

  operation(:update_reservation,
    summary: "Update reservation",
    responses: %{200 => {"Reservation", "application/json", DockdWeb.ApiSchemas.Error}}
  )

  operation(:delete_reservation,
    summary: "Delete reservation",
    responses: %{204 => {nil, "application/json", nil}}
  )

  def balances(conn, _),
    do: json(conn, %{data: Enum.map(Wallet.list_balances(Accounts.default_owner()), &encode/1)})

  def create_balance(conn, %{"balance" => attrs}) do
    case Wallet.create_balance(Accounts.default_owner(), attrs) do
      {:ok, balance} ->
        conn |> put_status(:created) |> json(%{data: encode(balance)})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: translate_errors(changeset)})
    end
  end

  def reservations(conn, _),
    do:
      json(conn, %{data: Enum.map(Wallet.list_reservations(Accounts.default_owner()), &encode/1)})

  def create_reservation(conn, %{"reservation" => attrs}) do
    case Wallet.create_reservation(Accounts.default_owner(), attrs) do
      {:ok, reservation} ->
        conn |> put_status(:created) |> json(%{data: encode(reservation)})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: translate_errors(changeset)})
    end
  end

  def update_balance(conn, %{"id" => id, "balance" => attrs}) do
    owner = Accounts.default_owner()

    with balance when not is_nil(balance) <- Wallet.get_balance!(owner, id),
         {:ok, balance} <- Wallet.update_balance(owner, balance, attrs),
         do: json(conn, %{data: encode(balance)})
  end

  def delete_balance(conn, %{"id" => id}) do
    owner = Accounts.default_owner()

    :ok =
      case Wallet.delete_balance(owner, Wallet.get_balance!(owner, id)) do
        {:ok, _} -> :ok
      end

    send_resp(conn, :no_content, "")
  end

  def update_reservation(conn, %{"id" => id, "reservation" => attrs}) do
    owner = Accounts.default_owner()
    reservation = Wallet.get_reservation!(owner, id)
    {:ok, reservation} = Wallet.update_reservation(owner, reservation, attrs)
    json(conn, %{data: encode(reservation)})
  end

  def delete_reservation(conn, %{"id" => id}) do
    owner = Accounts.default_owner()
    {:ok, _} = Wallet.delete_reservation(owner, Wallet.get_reservation!(owner, id))
    send_resp(conn, :no_content, "")
  end

  defp encode(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__, :user, :game])

  defp translate_errors(changeset),
    do:
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
end
