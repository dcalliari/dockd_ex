defmodule DockdWeb.PlannerLive do
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Planner
  alias Dockd.Wallet

  @impl true
  def mount(_params, _session, socket) do
    owner = Accounts.default_owner()
    summary = Planner.summary(owner)

    {:ok,
     assign(socket,
       page_title: "Planejador",
       owner: owner,
       summary: summary,
       balance_present?: Wallet.get_balance(owner, :eshop) != nil,
       decision_groups: decision_groups(summary.opportunities, summary.money)
     )}
  end

  defp decision_groups(opportunities, money) do
    opportunities = Enum.map(opportunities, &Map.put(&1, :money, money))

    [
      %{
        key: :buy,
        label: "Comprar agora",
        items: Enum.filter(opportunities, &(&1.verdict == :buy))
      },
      %{key: :wait, label: "Esperar", items: Enum.filter(opportunities, &(&1.verdict == :wait))},
      %{
        key: :record,
        label: "Sem preço",
        items: Enum.filter(opportunities, &(&1.verdict == :record_price))
      }
    ]
    |> Enum.filter(&(&1.items != []))
  end

  defp verdict_reason(item) do
    cond do
      is_nil(item.observation) ->
        "Sem preço"

      item.observation_stale? ->
        "Preço desatualizado"

      is_nil(item.entry.target_price_cents) ->
        "Sem alvo"

      item.observation.price_cents > item.entry.target_price_cents ->
        "#{money(item.observation.price_cents, item.observation.currency)} > alvo #{money(item.entry.target_price_cents, item.entry.currency)}"

      item.observation.price_cents > item_money_free(item) ->
        "#{money(item.observation.price_cents, item.observation.currency)} > livre"

      true ->
        "#{money(item.observation.price_cents, item.observation.currency)} < alvo #{money(item.entry.target_price_cents, item.entry.currency)}"
    end
  end

  defp item_money_free(item) do
    case item do
      %{money: %{free_cents: free_cents}} -> free_cents
      _ -> 0
    end
  end

  defp recommendation_reason(%{reason: reason}) do
    case Regex.run(~r/sem avanço há (\d+) dias/i, reason) do
      [_, days] -> "Parado há #{days} dias"
      _ -> "Na coleção"
    end
  end
end
