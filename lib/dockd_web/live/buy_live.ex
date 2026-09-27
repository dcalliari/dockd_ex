defmodule DockdWeb.BuyLive do
  @moduledoc """
  Comprar: the games in Quero by release date, each with its price and Comprei, under one
  line with the estimated total of the queue per media and what was spent this month
  (`design/maquetes/compra.html`). A game bought here stays in its place with Backlog and
  Desfazer until the screen is left.
  """
  use DockdWeb, :live_view

  on_mount {DockdWeb.UserAuth, :require_authenticated}

  alias Dockd.Catalog.Release
  alias Dockd.Library.Shelf
  alias Dockd.Purchasing
  alias DockdWeb.GameEvents

  @game_events GameEvents.events()
  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    {:ok, socket |> assign(page_title: "Comprar", user: user) |> GameEvents.init() |> load()}
  end

  defp load(socket) do
    %{user: user, bought: bought} = socket.assigns
    today = Date.utc_today()

    items =
      user
      |> Shelf.list()
      |> Enum.filter(&(&1.status == :quero or Map.has_key?(bought, &1.game.id)))
      |> Enum.map(&Map.put(&1, :first, Shelf.first_release(&1)))

    {dated, undated} = Enum.split_with(items, & &1.first.release_date)

    {upcoming, available} =
      Enum.split_with(dated, &(Date.compare(&1.first.release_date, today) == :gt))

    wanted = Enum.filter(items, &(&1.status == :quero))

    assign(socket,
      today: today,
      upcoming: Enum.sort_by(upcoming, &sort_key/1),
      available: Enum.sort_by(available, &sort_key/1, :desc),
      undated: undated,
      prices: Map.new(items, &{&1.game.id, Purchasing.current_game_price(user, &1.releases)}),
      estimate: Map.new([:physical, :digital], &{&1, estimate(user, wanted, &1)}),
      spent: Purchasing.month_spending(user, today)
    )
  end

  # The queue's total in one media: the price of every game sold in it that has one, and
  # how many of those games it covers.
  defp estimate(user, items, media) do
    sold =
      Enum.filter(items, fn item -> Enum.any?(item.releases, &(media in Release.media(&1))) end)

    prices =
      sold
      |> Enum.map(&Purchasing.current_game_price(user, &1.releases, media))
      |> Enum.reject(&is_nil/1)

    %{total: Enum.sum_by(prices, & &1.price_cents), priced: length(prices), of: length(sold)}
  end

  # A year-only date sorts after every dated release of the same year.
  defp sort_key(%{first: %{release_date: date, release_date_precision: :year}}),
    do: {date.year, 13, 0, ""}

  defp sort_key(%{first: %{release_date: date}, game: game}),
    do: {date.year, date.month, date.day, game.title}

  @impl true
  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &load/1)

  defp year_marks(items) do
    items
    |> Enum.chunk_by(& &1.first.release_date.year)
    |> Enum.map(&{hd(&1).first.release_date.year, &1})
  end

  defp month_name(%Date{month: month}), do: Enum.at(@months, month - 1)

  defp price_open?(%{kind: :price, key: key}, game_id), do: key == game_id
  defp price_open?(_form, _game_id), do: false

  attr :item, :map, required: true
  attr :price, :map, default: nil
  attr :form, :map, default: nil
  attr :error, :string, default: nil
  attr :buy, :boolean, default: true
  attr :buying, :any, default: nil
  attr :bought, :map, required: true
  attr :today, Date, required: true
  attr :thumb, :string, default: "poster", values: ~w(poster date)

  defp queue_row(assigns) do
    ~H"""
    <div id={"queue-#{@item.game.id}"}>
      <div class="dk-row dk-row--wide">
        <.date_block
          :if={@thumb == "date"}
          date={@item.first.release_date}
          precision={@item.first.release_date_precision}
          today={@today}
        />
        <.poster
          :if={@thumb == "poster"}
          title={@item.game.title}
          cover_url={@item.game.cover_url}
          size="sm"
          navigate={~p"/jogos/#{@item.game.id}"}
        />
        <div>
          <.link navigate={~p"/jogos/#{@item.game.id}"} class="dk-row__title">{@item.game.title}</.link>
          <div class="dk-row__meta">
            {meta([platform_label(@item.releases), enum_label(@item.game.availability)])}
          </div>
        </div>
        <div class="dk-row__end">
          <.price
            :if={!@bought[@item.game.id]}
            id={"price-#{@item.game.id}"}
            observation={@price}
            game_id={@item.game.id}
            open={price_open?(@form, @item.game.id)}
          />
          <.buy_control
            :if={@buy}
            id={"buy-#{@item.game.id}"}
            game_id={@item.game.id}
            choices={GameEvents.buying(@buying, @item.game.id)}
            purchase={@bought[@item.game.id]}
            form={@form}
            error={@error}
          />
        </div>
      </div>
      <.price_form
        :if={price_open?(@form, @item.game.id)}
        id={"price-form-#{@item.game.id}"}
        form={@form}
        error={@error}
      />
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current="Comprar">
      <p
        :if={@estimate.physical.priced > 0 or @estimate.digital.priced > 0 or @spent > 0}
        id="queue-totals"
        class="dk-totals"
      >
        <span
          :for={{media, label} <- [physical: "Físico", digital: "Digital"]}
          :if={@estimate[media].priced > 0}
          id={"estimate-#{media}"}
        >
          {label}<b>{money(@estimate[media].total)}</b><small>em {@estimate[media].priced} de {@estimate[
            media
          ].of}</small>
        </span>
        <span :if={@spent > 0} id="month-spending">
          Gasto em {month_name(@today)}<b>{money(@spent)}</b>
        </span>
      </p>

      <.section_head title="Próximos lançamentos" count={length(@upcoming)} />
      <%= for {{year, items}, index} <- Enum.with_index(year_marks(@upcoming)) do %>
        <p :if={index > 0} class="dk-year-mark">{year}</p>
        <.queue_row
          :for={item <- items}
          item={item}
          thumb="date"
          buy={false}
          price={@prices[item.game.id]}
          form={@form}
          error={@form_error}
          bought={@bought}
          today={@today}
        />
      <% end %>
      <.empty_state :if={@upcoming == []}>Nenhum lançamento na fila.</.empty_state>

      <.section_head title="Disponíveis" count={length(@available)} />
      <.queue_row
        :for={item <- @available}
        item={item}
        price={@prices[item.game.id]}
        form={@form}
        error={@form_error}
        buying={@buying}
        bought={@bought}
        today={@today}
      />
      <.empty_state :if={@available == []}>Nada disponível na fila.</.empty_state>

      <%= if @undated != [] do %>
        <.section_head title="Sem data" count={length(@undated)} />
        <.queue_row
          :for={item <- @undated}
          item={item}
          buy={false}
          price={@prices[item.game.id]}
          form={@form}
          error={@form_error}
          bought={@bought}
          today={@today}
        />
      <% end %>
    </Layouts.app>
    """
  end
end
