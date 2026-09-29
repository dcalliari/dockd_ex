defmodule DockdWeb.BuyLive do
  @moduledoc """
  Comprar: the games in Quero, the digital ones on sale first by when the sale ends, then
  by release date, each with its media, edition, price, Agora and Comprei, under one line
  with the total of the queue per media and what was spent this month, and the Agora
  subtotal per media (never combined, `design/maquetes/edicao-comprar.html`) on its own
  line below (`design/maquetes/planejador.html`, caminho A). With more than one edition,
  the EditionTag (`design/maquetes/edicao-comprar.html`, caminho A) opens a choice under
  the row: picking one pins the price and total to that release instead of the cheapest.
  A game bought here stays in its place with Backlog and Desfazer, and one on sale stays
  in Promoções, until the screen is left.
  """
  use DockdWeb, :live_view

  on_mount {DockdWeb.UserAuth, :require_authenticated}

  alias Dockd.Catalog
  alias Dockd.Catalog.Release
  alias Dockd.Library
  alias Dockd.Library.Shelf
  alias Dockd.{Pricing, Purchasing}
  alias DockdWeb.GameEvents

  @game_events GameEvents.events()
  @media %{"physical" => :physical, "digital" => :digital}
  @months ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(page_title: "Comprar", user: user, promotions: nil, editing: nil)
     |> GameEvents.init()
     |> load()}
  end

  defp load(socket) do
    %{user: user, bought: bought} = socket.assigns
    today = Date.utc_today()

    items =
      user
      |> Shelf.list()
      |> Enum.filter(&(&1.status == :quero or Map.has_key?(bought, &1.game.id)))
      |> Enum.map(
        &Map.merge(&1, %{first: Shelf.first_release(&1), media: Library.media(&1.entry)})
      )

    prices =
      Map.new(
        items,
        &{&1.game.id,
         Purchasing.current_game_price(
           user,
           &1.releases,
           &1.media,
           &1.entry.preferred_release_id
         )}
      )

    promotions = socket.assigns.promotions || promotions(items, prices)
    {promoted, queue} = Enum.split_with(items, &Map.has_key?(promotions, &1.game.id))

    sales = queue |> Enum.flat_map(& &1.releases) |> Enum.map(& &1.id) |> Pricing.sales_statuses()
    launches = Enum.group_by(queue, &launch(&1, today, sales))

    [upcoming, available, undated] =
      Enum.map([:upcoming, :released, :undated], &(launches[&1] || []))

    wanted = Enum.filter(items, &(&1.status == :quero))

    assign(socket,
      today: today,
      promotions: promotions,
      promoted: Enum.sort_by(promoted, &{promotions[&1.game.id], &1.game.title}, &sale_order/2),
      upcoming: Enum.sort_by(upcoming, &sort_key/1),
      available: Enum.sort_by(available, &sort_key/1, :desc),
      undated: undated,
      prices: prices,
      estimate: Map.new([:physical, :digital], &{&1, estimate(wanted, prices, &1)}),
      planned: planned_total(wanted, prices),
      spent: Purchasing.month_spending(user, today)
    )
  end

  # The digital wishes on sale when the screen opens, with when each sale ends. Kept
  # while the screen is open, so a row does not jump away after its media changes.
  defp promotions(items, prices) do
    for %{status: :quero, media: :digital, game: game} <- items,
        %{discount_ends_at: %DateTime{} = ends_at} <- [prices[game.id]],
        into: %{},
        do: {game.id, ends_at}
  end

  defp sale_order({ends_a, title_a}, {ends_b, title_b}),
    do: DateTime.compare(ends_a, ends_b) == :lt or (ends_a == ends_b and title_a <= title_b)

  # The queue's total in one media: the games to buy in it, and the price of every one
  # that has one.
  defp estimate(items, prices, media) do
    games = Enum.filter(items, &(&1.media == media))
    priced = games |> Enum.map(&prices[&1.game.id]) |> Enum.reject(&is_nil/1)

    %{total: Enum.sum_by(priced, & &1.price_cents), priced: length(priced), of: length(games)}
  end

  # Agora: what the games marked to buy now cost, digital and physical kept apart, never
  # summed into one number, since they compare against different balances.
  defp planned_total(items, prices) do
    planned = Enum.filter(items, &planned?/1)

    %{
      digital: planned_media_total(planned, prices, :digital),
      physical: planned_media_total(planned, prices, :physical)
    }
  end

  defp planned_media_total(planned, prices, media) do
    planned
    |> Enum.filter(&(&1.media == media))
    |> Enum.map(&prices[&1.game.id])
    |> Enum.reject(&is_nil/1)
    |> Enum.sum_by(& &1.price_cents)
  end

  defp planned?(%{entry: %{purchase_intent: :planned}}), do: true
  defp planned?(_item), do: false

  # Agora is offered on any wanted game with a price in its chosen media, not preordered.
  defp plannable?(item, price, bought),
    do:
      price != nil and not Map.has_key?(bought, item.game.id) and
        item.entry.purchase_intent in [:want, :planned]

  # Out once any version is; else upcoming by its first date, or undated.
  defp launch(item, today, sales) do
    launches = Enum.map(item.releases, &Release.launch(&1, today, sales[&1.id]))

    cond do
      :released in launches -> :released
      :upcoming in launches -> :upcoming
      true -> :undated
    end
  end

  # A year-only date sorts after every dated release of the same year.
  defp sort_key(%{first: %{release_date: date, release_date_precision: :year}}),
    do: {date.year, 13, 0, ""}

  defp sort_key(%{first: %{release_date: nil}, game: game}), do: {0, 0, 0, game.title}

  defp sort_key(%{first: %{release_date: date}, game: game}),
    do: {date.year, date.month, date.day, game.title}

  @impl true
  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, assign(socket, :editing, nil), &load/1)

  def handle_event("set_media", %{"game_id" => game_id, "media" => media}, socket) do
    case Map.fetch(@media, media) do
      {:ok, media} -> Library.set_media(socket.assigns.user, game_id, media)
      :error -> :ok
    end

    {:noreply, socket |> assign(:editing, nil) |> load()}
  end

  def handle_event("plan", %{"game_id" => game_id} = params, socket) do
    Library.plan(socket.assigns.user, game_id, params["planned"] == "true")
    {:noreply, load(socket)}
  end

  # The EditionTag toggles its own choice: a second tap on the same game closes it.
  def handle_event("edition_menu", %{"game_id" => game_id}, socket) do
    case socket.assigns.editing do
      %{game_id: ^game_id} ->
        {:noreply, assign(socket, :editing, nil)}

      _ ->
        {:noreply,
         socket
         |> GameEvents.init()
         |> assign(:editing, %{game_id: game_id, options: edition_options(socket, game_id)})}
    end
  end

  def handle_event(
        "set_edition",
        %{"game_id" => game_id, "release_id" => release_id},
        socket
      ) do
    Library.set_edition(socket.assigns.user, game_id, release_id)
    {:noreply, socket |> assign(:editing, nil) |> load()}
  end

  def handle_event("cancel_edition", _params, socket),
    do: {:noreply, assign(socket, :editing, nil)}

  # Each edition's own price, in the media the row already shows, for the choice under it.
  defp edition_options(socket, game_id) do
    user = socket.assigns.user
    media = user |> Library.get_entry_for_game(game_id) |> Library.media()
    releases = Catalog.get_game!(game_id).releases

    Enum.map(releases, &%{release: &1, price: Purchasing.current_price(user, &1.id, media)})
  end

  defp year_marks(items) do
    items
    |> Enum.chunk_by(& &1.first.release_date.year)
    |> Enum.map(&{hd(&1).first.release_date.year, &1})
  end

  defp month_name(%Date{month: month}), do: Enum.at(@months, month - 1)

  defp games_count(1), do: "1 jogo"
  defp games_count(count), do: "#{count} jogos"

  # Once bought here, the row says which version and edition it was.
  defp row_meta(item, %{release_id: release_id}) do
    case Enum.find(item.releases, &(&1.id == release_id)) do
      nil -> platform_label(item.releases)
      release -> release_label(release)
    end
  end

  # The EditionTag's closed label: the edition the account chose, or the one behind the
  # price shown, or Padrão when neither says otherwise.
  defp edition_tag_label(item, price) do
    preferred =
      item.entry.preferred_release_id &&
        Enum.find(item.releases, &(&1.id == item.entry.preferred_release_id))

    case preferred || price_release(price, item.releases) do
      nil -> "Padrão"
      release -> edition_label(release) || "Padrão"
    end
  end

  defp price_release(%{release_id: release_id}, releases) when is_binary(release_id),
    do: Enum.find(releases, &(&1.id == release_id))

  defp price_release(_price, _releases), do: nil

  attr :id, :string, required: true
  attr :game_id, :string, required: true
  attr :media, :atom, required: true

  # The MediaTag is the control, like the price and the status tag: one tap swaps it.
  defp media_toggle(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="dk-media"
      aria-label="Mídia preferida"
      phx-click="set_media"
      phx-value-game_id={@game_id}
      phx-value-media={if(@media == :physical, do: "digital", else: "physical")}
    >
      {enum_label(@media)}
    </button>
    """
  end

  defp price_open?(%{kind: :price, key: key}, game_id), do: key == game_id
  defp price_open?(_form, _game_id), do: false

  attr :id, :string, required: true
  attr :game_id, :string, required: true
  attr :label, :string, required: true

  # EditionTag: like the MediaTag, the current edition is the control, but with more than
  # two editions a tap opens the choice under the row instead of swapping in place.
  defp edition_tag(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="dk-media"
      aria-label="Edição"
      phx-click="edition_menu"
      phx-value-game_id={@game_id}
    >
      {@label}
    </button>
    """
  end

  defp edition_open?(%{game_id: game_id}, game_id), do: true
  defp edition_open?(_editing, _game_id), do: false

  attr :id, :string, required: true
  attr :game_id, :string, required: true
  attr :selected_id, :string, default: nil
  attr :options, :list, required: true

  # The choice is the action (design/components/bundle.css): picking an edition closes
  # the panel and the row's price and total follow it at once.
  defp edition_choice(assigns) do
    ~H"""
    <div id={@id} class="dk-form">
      <div class="dk-form__field">
        <span>Edição</span>
        <div class="dk-choice" role="radiogroup" aria-label="Edição">
          <button
            :for={option <- @options}
            type="button"
            aria-pressed={to_string(option.release.id == @selected_id)}
            phx-click="set_edition"
            phx-value-game_id={@game_id}
            phx-value-release_id={option.release.id}
          >
            {release_label(option.release)} · {option_price_text(option.price)}
          </button>
        </div>
      </div>
      <button type="button" class="dk-link" phx-click="cancel_edition">Cancelar</button>
    </div>
    """
  end

  defp option_price_text(nil), do: "Sem preço"
  defp option_price_text(price), do: money(price.price_cents, price.currency)

  attr :item, :map, required: true
  attr :price, :map, default: nil
  attr :form, :map, default: nil
  attr :error, :string, default: nil
  attr :buy, :boolean, default: true
  attr :buying, :any, default: nil
  attr :bought, :map, required: true
  attr :today, Date, required: true
  attr :thumb, :string, default: "poster", values: ~w(poster date)
  attr :plannable, :boolean, default: false
  attr :editing, :map, default: nil

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
          <div :if={@bought[@item.game.id]} class="dk-row__meta">
            {row_meta(@item, @bought[@item.game.id])}
          </div>
          <div :if={!@bought[@item.game.id]} class="dk-row__meta">
            {platform_label(@item.releases)}<.exclusive_mark availability={@item.game.availability} />
            ·
            <.media_toggle id={"media-#{@item.game.id}"} game_id={@item.game.id} media={@item.media} />
            <%= if length(@item.releases) > 1 do %>
              ·
              <.edition_tag
                id={"edition-#{@item.game.id}"}
                game_id={@item.game.id}
                label={edition_tag_label(@item, @price)}
              />
            <% end %>
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
          <div class="dk-row__acts">
            <.btn
              :if={@plannable}
              id={"plan-#{@item.game.id}"}
              size="sm"
              variant="secondary"
              aria-pressed={to_string(planned?(@item))}
              phx-click="plan"
              phx-value-game_id={@item.game.id}
              phx-value-planned={to_string(!planned?(@item))}
            >
              Agora
            </.btn>
            <.buy_control
              :if={@buy and !GameEvents.buy_options(@buying, @item.game.id)}
              id={"buy-#{@item.game.id}"}
              game_id={@item.game.id}
              choices={GameEvents.buying(@buying, @item.game.id)}
              purchase={@bought[@item.game.id]}
              form={@form}
              error={@error}
            />
          </div>
        </div>
      </div>
      <.buy_options
        :if={@buy and GameEvents.buy_options(@buying, @item.game.id)}
        id={"buy-options-#{@item.game.id}"}
        game_id={@item.game.id}
        options={GameEvents.buy_options(@buying, @item.game.id)}
      />
      <.price_form
        :if={price_open?(@form, @item.game.id)}
        id={"price-form-#{@item.game.id}"}
        form={@form}
        error={@error}
      />
      <.edition_choice
        :if={edition_open?(@editing, @item.game.id)}
        id={"edition-choice-#{@item.game.id}"}
        game_id={@item.game.id}
        selected_id={@item.entry.preferred_release_id}
        options={@editing.options}
      />
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      catalog_review={@catalog_review}
      current="Comprar"
    >
      <p
        :if={@estimate.digital.of > 0 or @estimate.physical.of > 0 or @spent > 0}
        id="queue-totals"
        class="dk-totals"
      >
        <span
          :for={{media, label} <- [digital: "Digital", physical: "Físico"]}
          :if={@estimate[media].of > 0}
          id={"estimate-#{media}"}
        >
          <%= if @estimate[media].priced > 0 do %>
            {label}<b>{money(@estimate[media].total)}</b><small>em {@estimate[media].priced} de {@estimate[
              media
            ].of}</small>
          <% else %>
            {label}<b class="dk-totals__none">Sem preço</b><small>{games_count(@estimate[media].of)}</small>
          <% end %>
        </span>
        <span :if={@spent > 0} id="month-spending">
          Gasto em {month_name(@today)}<b>{money(@spent)}</b>
        </span>
      </p>
      <p
        :if={@planned.digital > 0 or @planned.physical > 0}
        id="planned-totals"
        class="dk-totals"
      >
        <span :if={@planned.digital > 0} id="planned-total-digital">
          Agora digital<b>{money(@planned.digital)}</b>
        </span>
        <span :if={@planned.physical > 0} id="planned-total-physical">
          Agora físico<b>{money(@planned.physical)}</b>
        </span>
      </p>

      <%= if @promoted != [] do %>
        <.section_head title="Promoções" count={length(@promoted)} />
        <.queue_row
          :for={item <- @promoted}
          item={item}
          price={@prices[item.game.id]}
          plannable={plannable?(item, @prices[item.game.id], @bought)}
          form={@form}
          error={@form_error}
          buying={@buying}
          bought={@bought}
          today={@today}
          editing={@editing}
        />
      <% end %>

      <.section_head title="Próximos lançamentos" count={length(@upcoming)} />
      <%= for {{year, items}, index} <- Enum.with_index(year_marks(@upcoming)) do %>
        <p :if={index > 0} class="dk-year-mark">{year}</p>
        <.queue_row
          :for={item <- items}
          item={item}
          thumb="date"
          buy={false}
          price={@prices[item.game.id]}
          plannable={plannable?(item, @prices[item.game.id], @bought)}
          form={@form}
          error={@form_error}
          bought={@bought}
          today={@today}
          editing={@editing}
        />
      <% end %>
      <.empty_state :if={@upcoming == []}>Nenhum lançamento na fila.</.empty_state>

      <.section_head title="Disponíveis" count={length(@available)} />
      <.queue_row
        :for={item <- @available}
        item={item}
        price={@prices[item.game.id]}
        plannable={plannable?(item, @prices[item.game.id], @bought)}
        form={@form}
        error={@form_error}
        buying={@buying}
        bought={@bought}
        today={@today}
        editing={@editing}
      />
      <.empty_state :if={@available == []}>Nada disponível na fila.</.empty_state>

      <%= if @undated != [] do %>
        <.section_head title="Sem data" count={length(@undated)} />
        <.queue_row
          :for={item <- @undated}
          item={item}
          buy={false}
          price={@prices[item.game.id]}
          plannable={plannable?(item, @prices[item.game.id], @bought)}
          form={@form}
          error={@form_error}
          bought={@bought}
          today={@today}
          editing={@editing}
        />
      <% end %>
    </Layouts.app>
    """
  end
end
