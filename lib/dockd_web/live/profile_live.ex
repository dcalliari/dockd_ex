defmodule DockdWeb.ProfileLive do
  @moduledoc """
  Perfil público em `/u/:username` (`maquetes/perfil-completo.html`, retrato em movimento):
  cabeçalho com monograma, bio, local, link e números; favoritos escolhidos, Jogando agora
  e o Diário por mês na coluna principal, com a barra da estante, o Quero e os zerados do
  ano na lateral; as listas de seguidores e seguindo; as grades completas de status; e o
  Diário inteiro (`maquetes/perfil-diario.html`, caminho A), uma linha por troca de status
  com o bloco de data na primeira do dia. As capas levam a etiqueta de quem olha, como em
  Descobrir.

  O perfil é aberto na web por padrão; com Só amigos, quem não é amigo vê só o nome, as
  contagens e o botão Seguir.
  """
  use DockdWeb, :live_view

  alias Dockd.Accounts.User
  alias Dockd.{Catalog, Library, Repo, Social}
  alias Dockd.Catalog.Game
  alias Dockd.Library.Shelf
  alias DockdWeb.{GameEvents, UserAuth}

  @game_events GameEvents.events()
  @day 10
  @now 4
  @fan 5
  @diary_rows 8
  @sections [
    jogando: {"Jogando agora", "jogando"},
    zerado: {"Zerados", "zerados"},
    quero: {"Quero", "quero"}
  ]

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    owner = Social.get_profile!(username)
    viewer = socket.assigns.current_scope && socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(owner: owner, user: viewer, page_title: owner.name)
     |> assign(year: Date.utc_today().year, stats: nil, summary: nil)
     |> assign(picker: nil, q: "", results: [], slots: [])
     |> assign(open_days: MapSet.new())
     |> GameEvents.init()
     |> UserAuth.halt_visitor_events([
       "pick_slot",
       "search_favorites",
       "choose_favorite",
       "clear_favorite",
       "move_favorite",
       "more_day"
     ])
     |> load()}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("follow", %{"username" => username}, socket) do
    :ok = Social.follow(socket.assigns.user, Social.get_profile!(username))
    {:noreply, load(socket)}
  end

  def handle_event("unfollow", %{"username" => username}, socket) do
    :ok = Social.unfollow(socket.assigns.user, Social.get_profile!(username))
    {:noreply, load(socket)}
  end

  def handle_event("open_picker", %{"position" => position}, socket) do
    if socket.assigns.relation == :self do
      {:noreply, assign(socket, picker: slot_number(position), q: "", results: [])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_picker", _params, socket), do: {:noreply, assign(socket, picker: nil)}

  def handle_event("search_favorites", %{"q" => q}, socket) do
    taken = socket.assigns.favorites |> Enum.map(& &1.game_id) |> MapSet.new()

    results =
      q
      |> Catalog.search()
      |> Enum.reject(&MapSet.member?(taken, &1.game.id))

    {:noreply, assign(socket, q: String.trim(q), results: results)}
  end

  def handle_event("choose_favorite", %{"game_id" => game_id}, socket) do
    with %{relation: :self, picker: position} when not is_nil(position) <- socket.assigns,
         %Game{} = game <- Repo.get(Game, game_id) do
      result = Social.put_favorite(socket.assigns.owner, game, position)
      {:noreply, socket |> assign(picker: nil) |> favorite_result(result)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Dragging a cover onto a position, or the arrow keys, moves a favorite there; the one
  # already there swaps into its old position.
  def handle_event("place_favorite", %{"game_id" => game_id, "position" => position}, socket) do
    with %{relation: :self} <- socket.assigns,
         %Game{} = game <- Repo.get(Game, game_id),
         position when position in 1..4 <- slot_number(position) do
      result = Social.put_favorite(socket.assigns.owner, game, position)
      {:noreply, favorite_result(socket, result)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_favorite", %{"position" => position}, socket) do
    with %{relation: :self} <- socket.assigns,
         position when position in 1..4 <- slot_number(position) do
      result = Social.clear_favorite(socket.assigns.owner, position)
      {:noreply, favorite_result(socket, result)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("more_day", %{"day" => day}, socket),
    do: {:noreply, update(socket, :open_days, &MapSet.put(&1, Date.from_iso8601!(day)))}

  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &load/1)

  defp favorite_result(socket, result) when result == :ok, do: load(socket)
  defp favorite_result(socket, {:error, _reason}), do: load(socket)

  defp slot_number(position) do
    case Integer.parse(position) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp load(%{assigns: %{owner: owner, user: viewer}} = socket) do
    relation = Social.relation(viewer, owner)
    visible = Social.visible?(owner, relation)

    socket
    |> assign(
      relation: relation,
      visible: visible,
      counts: Social.counts(owner)
    )
    |> load_view(visible)
  end

  defp load_view(socket, false), do: socket

  defp load_view(%{assigns: %{live_action: action}} = socket, true)
       when action in [:followers, :following] do
    assign(socket, people: Social.people(socket.assigns.owner, action, socket.assigns.user))
  end

  defp load_view(%{assigns: %{live_action: :diary, owner: owner}} = socket, true) do
    entries = Social.diary(owner)

    assign(socket,
      diary_count: length(entries),
      diary: Enum.chunk_by(entries, &DateTime.to_date(&1.at))
    )
  end

  defp load_view(
         %{assigns: %{owner: owner, user: viewer, live_action: action, relation: relation}} =
           socket,
         true
       ) do
    mine = if viewer, do: viewer |> Shelf.list() |> Map.new(&{&1.game.id, &1}), else: %{}
    slots = if relation == :self, do: Social.favorite_slots(owner), else: []

    favorites =
      if relation == :self, do: Enum.reject(slots, &is_nil/1), else: Social.favorites(owner)

    diary = if action == :show, do: Social.diary(owner), else: []

    assign(socket,
      shelf: Social.shelf(owner),
      favorites: favorites,
      slots: slots,
      stats: if(action == :show, do: Social.profile_stats(owner)),
      summary: if(action == :show, do: Social.year_summary(diary, socket.assigns.year)),
      diary_months: Social.diary_months(diary, @diary_rows),
      mine: mine
    )
  end

  # The viewer's own shelf item for a game on this profile, so the cover carries the
  # viewer's status control, as in Descobrir.
  defp mine(mine, %Shelf{game: game} = item),
    do: mine[game.id] || %{item | status: nil, ownerships: []}

  defp section_path(%User{username: username}, status),
    do: "/u/#{username}/#{elem(@sections[status], 1)}"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, sections: @sections, day: @day, now: @now, fan: @fan)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} catalog_review={@catalog_review}>
      <p :if={@live_action != :show} class="dk-back">
        <.link id="profile-back" navigate={~p"/u/#{@owner.username}"} class="dk-link">
          <.icon name="hero-arrow-left" /> {@owner.name}
        </.link>
      </p>

      <.profile_head
        :if={@live_action == :show}
        owner={@owner}
        counts={@counts}
        relation={@relation}
        links={@visible}
        year={@year}
        games={@stats && @stats.games}
        records={@summary && @summary.records}
      />

      <.empty_state :if={!@visible} id="profile-closed">Perfil só para amigos.</.empty_state>

      <%= if @visible do %>
        <%= case @live_action do %>
          <% :show -> %>
            <div id="profile-layout" class="dk-profile-layout">
              <section class="dk-profile-main">
                <%= if @favorites != [] || @relation == :self do %>
                  <.section_head id="profile-favorites" title="Favoritos" />
                  <%= if @relation == :self do %>
                    <div
                      id="profile-favorites-grid"
                      class="dk-profile-favorites"
                      phx-hook="FavoriteSlots"
                      aria-description="Arraste uma capa, ou use as setas esquerda e direita, para mudar a ordem"
                    >
                      <%= for {favorite, index} <- Enum.with_index(@slots, 1) do %>
                        <.favorite_card :if={favorite} favorite={favorite} editable />
                        <div
                          :if={!favorite}
                          id={"favorite-slot-#{index}"}
                          class="dk-fav-slot"
                          data-position={index}
                        >
                          <button
                            id={"favorite-add-#{index}"}
                            type="button"
                            class="dk-fav-add"
                            phx-click="open_picker"
                            phx-value-position={index}
                            aria-label={"Adicionar favorito na posição #{index}"}
                          >
                            <.icon name="hero-plus" />
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div id="profile-favorites-grid" class="dk-profile-favorites">
                      <.favorite_card :for={favorite <- @favorites} favorite={favorite} />
                    </div>
                  <% end %>
                <% end %>

                <%= if @shelf.jogando != [] do %>
                  <.section_head id="profile-playing" title="Jogando agora">
                    <:action>
                      <.link navigate={section_path(@owner, :jogando)}>Ver todos</.link>
                    </:action>
                  </.section_head>
                  <div id="profile-playing-now" class="dk-profile-now">
                    <.profile_card
                      :for={item <- Enum.take(@shelf.jogando, @now)}
                      item={mine(@mine, item)}
                      rail={:now}
                      user={@user}
                      asking={@asking}
                      back={~p"/u/#{@owner.username}"}
                    />
                  </div>
                <% end %>

                <%= if @diary_months != [] do %>
                  <.section_head id="profile-recent" title="Diário">
                    <:action>
                      <.link id="profile-diary-link" navigate={~p"/u/#{@owner.username}/diario"}>
                        Ver diário
                      </.link>
                    </:action>
                  </.section_head>
                  <div id="profile-diary-months">
                    <.diary_month
                      :for={{month, entries} <- @diary_months}
                      month={month}
                      entries={entries}
                    />
                  </div>
                <% end %>

                <.empty_state
                  :if={@favorites == [] && @shelf.jogando == [] && @diary_months == []}
                  id="profile-empty"
                >
                  Nada no perfil ainda.
                </.empty_state>
              </section>

              <aside id="profile-sidebar" class="dk-profile-sidebar">
                <.profile_shelf stats={@stats} owner={@owner} />
                <.profile_wishlist
                  :if={@shelf.quero != []}
                  owner={@owner}
                  items={@shelf.quero}
                  fan={@fan}
                />
                <.profile_finished
                  :if={Enum.sum(@summary.finished) > 0}
                  summary={@summary}
                  year={@year}
                />
              </aside>
            </div>
          <% :diary -> %>
            <.section_head id="profile-diary" title="Diário" count={@diary_count} />
            <div id="diary">
              <%= for [first | _] = entries <- @diary do %>
                <.diary_entry
                  :for={
                    {entry, index} <-
                      Enum.with_index(Enum.take(entries, day_limit(@open_days, entries, @day)))
                  }
                  entry={entry}
                  first={index == 0}
                />
                <div
                  :if={length(entries) > day_limit(@open_days, entries, @day)}
                  class="dk-entry dk-entry--more"
                >
                  <button
                    id={"diary-more-#{Date.to_iso8601(DateTime.to_date(first.at))}"}
                    type="button"
                    class="dk-link"
                    phx-click="more_day"
                    phx-value-day={Date.to_iso8601(DateTime.to_date(first.at))}
                  >
                    Mais {length(entries) - @day} neste dia
                  </button>
                </div>
              <% end %>
            </div>
            <.empty_state :if={@diary == []} id="diary-empty">Nada no diário ainda.</.empty_state>
          <% action when action in [:followers, :following] -> %>
            <.tabs id="profile-people-tabs">
              <:tab
                label="Seguindo"
                count={@counts.following}
                selected={@live_action == :following}
                patch={~p"/u/#{@owner.username}/seguindo"}
              />
              <:tab
                label="Seguidores"
                count={@counts.followers}
                selected={@live_action == :followers}
                patch={~p"/u/#{@owner.username}/seguidores"}
              />
            </.tabs>
            <div id="profile-people">
              <.person_row :for={person <- @people} person={person} />
            </div>
            <.empty_state :if={@people == []} id="profile-people-empty">
              {if(@live_action == :followers,
                do: "Ninguém segue ainda.",
                else: "Não segue ninguém ainda."
              )}
            </.empty_state>
          <% status -> %>
            <.section_head
              id={"profile-#{status}"}
              title={elem(@sections[status], 0)}
              count={length(@shelf[status])}
            />
            <div id={"profile-#{status}-grid"} class="dk-grid">
              <.profile_card
                :for={item <- @shelf[status]}
                item={mine(@mine, item)}
                rail={status}
                user={@user}
                asking={@asking}
                back={section_path(@owner, status)}
              />
            </div>
        <% end %>
      <% end %>

      <div
        :if={@picker}
        id="favorite-picker"
        class="dk-modal"
        role="presentation"
        phx-hook="FavoritePicker"
      >
        <section
          class="dk-modal__panel dk-modal__panel--wide"
          role="dialog"
          aria-modal="true"
          aria-labelledby="favorite-picker-title"
          phx-window-keydown="close_picker"
          phx-key="Escape"
          phx-click-away="close_picker"
        >
          <div class="dk-modal__head">
            <h2 id="favorite-picker-title">Escolher favorito</h2>
            <button id="favorite-picker-close" type="button" class="dk-link" phx-click="close_picker">
              Fechar
            </button>
          </div>
          <form
            id="favorite-search-form"
            class="dk-search"
            role="search"
            phx-change="search_favorites"
            phx-submit="search_favorites"
          >
            <.icon name="hero-magnifying-glass" />
            <input
              id="favorite-search"
              type="search"
              name="q"
              value={@q}
              placeholder="Buscar no catálogo"
              aria-label="Buscar no catálogo"
              autocomplete="off"
              phx-debounce="300"
              autofocus
            />
          </form>
          <div id="favorite-results" class="dk-modal__results">
            <div :for={result <- @results} id={"favorite-result-#{result.game.id}"} class="dk-row">
              <.poster
                title={result.game.title}
                cover_url={result.game.cover_url}
                size="sm"
              />
              <div>
                <b class="dk-row__title">{result.game.title}</b>
                <div class="dk-row__meta">{platform_label(result.game.releases)}</div>
              </div>
              <div class="dk-row__end">
                <button
                  id={"favorite-choose-#{result.game.id}"}
                  type="button"
                  class="dk-btn dk-btn--secondary"
                  phx-click="choose_favorite"
                  phx-value-game_id={result.game.id}
                >
                  Escolher
                </button>
              </div>
            </div>
            <.empty_state :if={@q != "" and @results == []} id="favorite-empty">
              Nenhum jogo encontrado.
            </.empty_state>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # Um dia cheio mostra dez linhas até Mais N abrir o resto no lugar.
  defp day_limit(open_days, [first | _] = entries, day) do
    if MapSet.member?(open_days, DateTime.to_date(first.at)), do: length(entries), else: day
  end

  attr :entry, :map, required: true
  attr :first, :boolean, required: true

  # DiaryEntry: a data abre o dia, a etiqueta diz o que a pessoa marcou.
  defp diary_entry(assigns) do
    ~H"""
    <div
      id={"diary-#{@entry.id}"}
      class={["dk-entry", @first && "dk-entry--first"]}
      data-status={@entry.status}
    >
      <div class="dk-entry__date">
        <.date_block :if={@first} date={DateTime.to_date(@entry.at)} release={false} />
      </div>
      <.poster
        title={@entry.item.game.title}
        cover_url={@entry.item.game.cover_url}
        navigate={~p"/jogos/#{@entry.item.game.id}"}
        size="sm"
      />
      <div class="dk-entry__text">
        <.link navigate={~p"/jogos/#{@entry.item.game.id}"} class="dk-row__title">
          {@entry.item.game.title}
        </.link>
        <div class="dk-row__meta">
          {platform_label(@entry.item.releases)}<.exclusive_mark availability={
            @entry.item.game.availability
          } />
        </div>
      </div>
      <.status_chip status={@entry.status} size="sm" />
    </div>
    """
  end

  attr :favorite, :map, required: true
  attr :editable, :boolean, default: false

  # For the owner the card is a draggable position (hook FavoriteSlots): the X clears it,
  # shown on hover and focus, and the arrow keys move it.
  defp favorite_card(assigns) do
    ~H"""
    <div
      id={"profile-favorite-#{@favorite.game_id}"}
      class={["dk-card", @editable && "dk-fav-slot"]}
      data-game-id={@editable && @favorite.game_id}
      data-position={@editable && @favorite.position}
    >
      <.poster
        title={@favorite.game.title}
        cover_url={@favorite.game.cover_url}
        availability={@favorite.game.availability}
        navigate={~p"/jogos/#{@favorite.game.id}"}
      />
      <button
        :if={@editable}
        id={"favorite-remove-#{@favorite.position}"}
        type="button"
        class="dk-fav-remove"
        phx-click="clear_favorite"
        phx-value-position={@favorite.position}
        aria-label={"Remover #{@favorite.game.title} dos favoritos"}
      >
        <.icon name="hero-x-mark" />
      </button>
      <.link navigate={~p"/jogos/#{@favorite.game.id}"} class="dk-card__text">
        <span class="dk-card__title">{@favorite.game.title}</span>
      </.link>
    </div>
    """
  end

  @month_labels ~w(JAN FEV MAR ABR MAI JUN JUL AGO SET OUT NOV DEZ)

  attr :month, Date, required: true
  attr :entries, :list, required: true

  # A month of the Diário on the profile: the DateBlock once, then one line per record with
  # its day, so the page reads as a ledger and not as a second Início.
  defp diary_month(assigns) do
    ~H"""
    <div id={"profile-month-#{Date.to_iso8601(@month)}"} class="dk-month">
      <.date_block date={@month} precision={:month} release={false} />
      <div class="dk-month__days">
        <div :for={entry <- @entries} id={"profile-diary-#{entry.id}"} class="dk-month__day">
          <span class="dk-month__d">{DateTime.to_date(entry.at).day}</span>
          <.poster
            title={entry.item.game.title}
            cover_url={entry.item.game.cover_url}
            navigate={~p"/jogos/#{entry.item.game.id}"}
            size="sm"
          />
          <.link navigate={~p"/jogos/#{entry.item.game.id}"} class="dk-month__title">
            {entry.item.game.title}
          </.link>
          <.status_chip status={entry.status} size="sm" />
        </div>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true
  attr :owner, :map, required: true

  # The Estante bar: the library by the six statuses, the same colors as their tags.
  defp profile_shelf(assigns) do
    assigns =
      assign(assigns, :rows, Enum.filter(Shelf.statuses(), &(assigns.stats.statuses[&1] > 0)))

    ~H"""
    <section :if={@rows != []} id="profile-stats">
      <.section_head id="profile-stats-head" title="Estante" />
      <div class="dk-profile-bar" role="img" aria-label="Jogos por status">
        <i
          :for={status <- @rows}
          class={"dk-profile-bar__#{status}"}
          style={"flex: #{@stats.statuses[status]}"}
        ></i>
      </div>
      <div class="dk-profile-legend">
        <%= for status <- @rows do %>
          <.link
            :if={status in [:jogando, :zerado, :quero]}
            id={"profile-stat-#{status}"}
            navigate={section_path(@owner, status)}
          >
            <span class={"dk-profile-legend__#{status}"}>{status_label(status)}</span>
            <b>{@stats.statuses[status]}</b>
          </.link>
          <div :if={status not in [:jogando, :zerado, :quero]} id={"profile-stat-#{status}"}>
            <span class={"dk-profile-legend__#{status}"}>{status_label(status)}</span>
            <b>{@stats.statuses[status]}</b>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  attr :owner, :map, required: true
  attr :items, :list, required: true
  attr :fan, :integer, required: true

  defp profile_wishlist(assigns) do
    ~H"""
    <section id="profile-wishlist">
      <.section_head id="profile-wishlist-head" title="Quero">
        <:action>
          <.link id="profile-wishlist-link" navigate={section_path(@owner, :quero)}>Ver todos</.link>
        </:action>
      </.section_head>
      <div id="profile-wishlist-fan" class="dk-profile-fan">
        <.poster
          :for={item <- Enum.take(@items, @fan)}
          title={item.game.title}
          cover_url={item.game.cover_url}
          navigate={~p"/jogos/#{item.game.id}"}
        />
      </div>
    </section>
    """
  end

  attr :summary, :map, required: true
  attr :year, :integer, required: true

  defp profile_finished(assigns) do
    assigns = assign(assigns, max: Enum.max(assigns.summary.finished), labels: @month_labels)

    ~H"""
    <section id="profile-finished">
      <.section_head id="profile-finished-head" title={"Zerados em #{@year}"} />
      <div class="dk-profile-histo" role="img" aria-label={"Zerados por mês em #{@year}"}>
        <i
          :for={{count, label} <- Enum.zip(@summary.finished, @labels)}
          title={"#{label}: #{count}"}
          class={count > 0 && "is-on"}
          style={"height: #{if(count > 0, do: round(count / @max * 100), else: 6)}%"}
        ></i>
      </div>
      <p class="dk-profile-histo__axis"><span>JAN</span><span>JUN</span><span>DEZ</span></p>
    </section>
    """
  end

  attr :item, :map, required: true
  attr :rail, :atom, required: true
  attr :user, :map, required: true
  attr :asking, :map, required: true
  attr :back, :string, required: true

  defp profile_card(assigns) do
    ~H"""
    <div id={"profile-#{@rail}-#{@item.game.id}"} class="dk-card" data-status={@item.status}>
      <.poster
        title={@item.game.title}
        cover_url={@item.game.cover_url}
        faded={@item.status in [:zerado, :larguei]}
        availability={@item.game.availability}
        navigate={~p"/jogos/#{@item.game.id}"}
      />
      <.status_link :if={!@user} back={@back} />
      <.status_menu
        :if={@user}
        id={"profile-status-#{@rail}-#{@item.game.id}"}
        status={@item.status}
        options={Library.status_options(@item)}
        values={%{game_id: @item.game.id}}
        ask={GameEvents.ask(@asking, @item)}
      />
      <.link navigate={~p"/jogos/#{@item.game.id}"} class="dk-card__text">
        <span class="dk-card__title">{@item.game.title}</span>
        <span class="dk-card__meta">{platform_label(@item.releases)}</span>
      </.link>
    </div>
    """
  end
end
