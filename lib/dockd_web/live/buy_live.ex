defmodule DockdWeb.BuyLive do
  @moduledoc "Comprar: a fila dos jogos em Quero, por data de lançamento, com saldo do eShop."
  use DockdWeb, :live_view

  on_mount {DockdWeb.UserAuth, :require_authenticated}

  alias Dockd.Library.Shelf
  alias Dockd.{Purchasing, Wallet}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    {:ok, socket |> assign(page_title: "Comprar", user: user, form: nil) |> load()}
  end

  defp load(socket) do
    %{user: user} = socket.assigns
    today = Date.utc_today()

    items =
      user
      |> Shelf.list()
      |> Enum.filter(&(&1.status == :quero))
      |> Enum.map(&Map.put(&1, :first, first_release(&1)))

    {dated, undated} = Enum.split_with(items, & &1.first.release_date)

    {upcoming, available} =
      Enum.split_with(dated, &(Date.compare(&1.first.release_date, today) == :gt))

    observations =
      Map.new(items, fn item ->
        {item.game.id, item.first && Purchasing.latest_price_observation(user, item.first.id)}
      end)

    balances = Wallet.list_balances(user)
    reservations = Wallet.list_reservations(user)

    assign(socket,
      today: today,
      upcoming: Enum.sort_by(upcoming, &sort_key/1),
      available: Enum.sort_by(available, &sort_key/1, :desc),
      undated: undated,
      observations: observations,
      balance: Enum.reduce(balances, 0, &(&1.amount_cents + &2)),
      reserved: Enum.reduce(reservations, 0, &(&1.amount_cents + &2)),
      reserved_games: MapSet.new(reservations, & &1.game_id),
      has_wallet: balances != [] or reservations != []
    )
  end

  defp first_release(%Shelf{releases: releases}) do
    releases
    |> Enum.sort_by(&{is_nil(&1.release_date), &1.release_date}, fn
      {nil_a, a}, {nil_b, b} when nil_a == nil_b and not is_nil(a) -> Date.compare(a, b) != :gt
      {nil_a, _}, {nil_b, _} -> nil_a <= nil_b
    end)
    |> List.first()
  end

  # A year-only date sorts after every dated release of the same year.
  defp sort_key(%{first: %{release_date: date, release_date_precision: :year}}),
    do: {date.year, 13, 0, ""}

  defp sort_key(%{first: %{release_date: date}, game: game}),
    do: {date.year, date.month, date.day, game.title}

  @impl true
  def handle_event("reserve_form", %{"game_id" => game_id}, socket),
    do: {:noreply, assign(socket, form: {:reserve, game_id})}

  def handle_event("buy_form", %{"game_id" => game_id}, socket),
    do: {:noreply, assign(socket, form: {:buy, game_id})}

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, form: nil)}

  def handle_event("save_reservation", %{"game_id" => game_id} = params, socket) do
    with {:ok, cents} when is_integer(cents) <- parse_money(params["amount"]),
         {:ok, _} <-
           Wallet.create_reservation(socket.assigns.user, %{
             game_id: game_id,
             store: :eshop,
             amount_cents: cents
           }) do
      {:noreply, socket |> assign(form: nil) |> load()}
    else
      :error -> {:noreply, put_flash(socket, :error, "Valor inválido. Use 199,90.")}
      _ -> {:noreply, put_flash(socket, :error, "Informe o valor reservado.")}
    end
  end

  def handle_event("save_purchase", %{"release_id" => release_id} = params, socket) do
    with {:ok, cents} when is_integer(cents) <- parse_money(params["price"]),
         {:ok, _} <-
           Purchasing.create_purchase(socket.assigns.user, %{
             release_id: release_id,
             format: params["format"] || "digital",
             price_cents: cents,
             purchased_at: DateTime.utc_now(),
             retailer: if(params["retailer"] in [nil, ""], do: "eShop", else: params["retailer"])
           }) do
      {:noreply, socket |> assign(form: nil) |> load()}
    else
      :error -> {:noreply, put_flash(socket, :error, "Preço inválido. Use 199,90.")}
      _ -> {:noreply, put_flash(socket, :error, "Informe o preço pago.")}
    end
  end

  defp default_price(nil), do: ""

  defp default_price(observation),
    do: observation.price_cents |> money() |> String.replace("R$ ", "")

  defp year_marks(items) do
    items
    |> Enum.chunk_by(& &1.first.release_date.year)
    |> Enum.map(&{hd(&1).first.release_date.year, &1})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current="Comprar">
      <p :if={@has_wallet} id="wallet-line" class="dk-wallet">
        <span>Saldo eShop<b>{money(@balance)}</b></span>
        <span :if={@reserved > 0}>Reservado<b>{money(@reserved)}</b></span>
      </p>

      <.section_head title="Próximos lançamentos" count={length(@upcoming)} />
      <%= for {{year, items}, index} <- Enum.with_index(year_marks(@upcoming)) do %>
        <p :if={index > 0} class="dk-year-mark">{year}</p>
        <div :for={item <- items} id={"queue-#{item.game.id}"}>
          <div class="dk-row">
            <.date_block
              date={item.first.release_date}
              precision={item.first.release_date_precision}
              today={@today}
            />
            <div>
              <.link navigate={~p"/jogos/#{item.game.id}"} class="dk-row__title">{item.game.title}</.link>
              <div class="dk-row__meta">
                {meta([platform_label(item.releases), enum_label(item.game.availability)])}
              </div>
            </div>
            <div class="dk-row__end">
              <span :if={MapSet.member?(@reserved_games, item.game.id)} class="dk-media">Reservado</span>
              <.btn
                :if={!MapSet.member?(@reserved_games, item.game.id)}
                size="sm"
                phx-click="reserve_form"
                phx-value-game_id={item.game.id}
              >
                Reservar
              </.btn>
            </div>
          </div>
          <form
            :if={@form == {:reserve, item.game.id}}
            id={"reserve-form-#{item.game.id}"}
            class="dk-inline-form"
            phx-submit="save_reservation"
          >
            <input type="hidden" name="game_id" value={item.game.id} />
            <input
              type="text"
              name="amount"
              inputmode="decimal"
              placeholder="349,90"
              aria-label="Valor reservado"
              autofocus
            />
            <.btn type="submit" size="sm" variant="primary">Reservar</.btn>
            <button type="button" class="dk-link" phx-click="cancel">Cancelar</button>
          </form>
        </div>
      <% end %>
      <.empty_state :if={@upcoming == []}>Nenhum lançamento na fila.</.empty_state>

      <.section_head title="Disponíveis" count={length(@available)} />
      <div :for={item <- @available} id={"queue-#{item.game.id}"}>
        <div class="dk-row dk-row--wide">
          <.poster
            title={item.game.title}
            cover_url={item.game.cover_url}
            size="sm"
            navigate={~p"/jogos/#{item.game.id}"}
          />
          <div>
            <.link navigate={~p"/jogos/#{item.game.id}"} class="dk-row__title">{item.game.title}</.link>
            <div class="dk-row__meta">
              {meta([platform_label(item.releases), enum_label(item.game.availability)])}
            </div>
          </div>
          <div class="dk-row__end">
            <.price observation={@observations[item.game.id]} />
            <.btn size="sm" phx-click="buy_form" phx-value-game_id={item.game.id}>Comprei</.btn>
          </div>
        </div>
        <form
          :if={@form == {:buy, item.game.id}}
          id={"buy-form-#{item.game.id}"}
          class="dk-inline-form"
          phx-submit="save_purchase"
        >
          <select :if={length(item.releases) > 1} name="release_id" aria-label="Versão">
            <option :for={release <- item.releases} value={release.id}>
              {enum_label(release.platform)}
            </option>
          </select>
          <input
            :if={length(item.releases) == 1}
            type="hidden"
            name="release_id"
            value={item.first.id}
          />
          <input
            type="text"
            name="price"
            inputmode="decimal"
            placeholder="199,90"
            aria-label="Preço pago"
            value={default_price(@observations[item.game.id])}
            autofocus
          />
          <select name="format" aria-label="Mídia">
            <option value="digital">Digital</option>
            <option value="physical">Físico</option>
          </select>
          <input type="text" name="retailer" placeholder="eShop" aria-label="Onde comprou" />
          <.btn type="submit" size="sm" variant="primary">Comprei</.btn>
          <button type="button" class="dk-link" phx-click="cancel">Cancelar</button>
        </form>
      </div>
      <.empty_state :if={@available == []}>Nada disponível na fila.</.empty_state>

      <%= if @undated != [] do %>
        <.section_head title="Sem data" count={length(@undated)} />
        <div :for={item <- @undated} id={"queue-#{item.game.id}"} class="dk-row">
          <.poster
            title={item.game.title}
            cover_url={item.game.cover_url}
            size="sm"
            navigate={~p"/jogos/#{item.game.id}"}
          />
          <div>
            <.link navigate={~p"/jogos/#{item.game.id}"} class="dk-row__title">{item.game.title}</.link>
            <div class="dk-row__meta">
              {meta([platform_label(item.releases), enum_label(item.game.availability)])}
            </div>
          </div>
          <div class="dk-row__end"></div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
