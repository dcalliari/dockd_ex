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

  defp encode(struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__, :user, :game])

  defp translate_errors(changeset),
    do:
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
end
