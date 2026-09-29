defmodule DockdWeb.ProfileLive do
  @moduledoc """
  Perfil público em `/u/:username` (`maquetes/perfil-social.html`, Estante): Jogando,
  Zerados e Quero em faixas e o Recente em linhas; as listas de seguidores e seguindo; e a
  grade inteira de uma faixa; e o Diário (`maquetes/perfil-diario.html`, caminho A), uma
  linha por troca de status com o bloco de data na primeira do dia. As capas levam a
  etiqueta de quem olha, como em Descobrir.

  O perfil é aberto na web por padrão; com Só amigos, quem não é amigo vê só o nome, as
  contagens e o botão Seguir.
  """
  use DockdWeb, :live_view

  alias Dockd.Accounts.User
  alias Dockd.{Library, Social}
  alias Dockd.Library.Shelf
  alias DockdWeb.{GameEvents, UserAuth}

  @game_events GameEvents.events()
  @strip 7
  @day 10
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
     |> assign(open_days: MapSet.new())
     |> GameEvents.init()
     |> UserAuth.halt_visitor_events(["more_day"])
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

  def handle_event("more_day", %{"day" => day}, socket),
    do: {:noreply, update(socket, :open_days, &MapSet.put(&1, Date.from_iso8601!(day)))}

  def handle_event("set_visibility", %{"visibility" => visibility}, socket) do
    %{owner: owner, user: user} = socket.assigns

    if owner.id == user.id do
      {:ok, owner} = Social.set_visibility(owner, visibility)
      {:noreply, socket |> assign(owner: owner) |> load()}
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, params, socket) when event in @game_events,
    do: GameEvents.handle_event(event, params, socket, &load/1)

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

  defp load_view(%{assigns: %{owner: owner, user: viewer}} = socket, true) do
    mine = if viewer, do: viewer |> Shelf.list() |> Map.new(&{&1.game.id, &1}), else: %{}

    assign(socket,
      shelf: Social.shelf(owner),
      recent: if(socket.assigns.live_action == :show, do: Social.recent(owner), else: []),
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
    assigns = assign(assigns, strip: @strip, sections: @sections, day: @day)

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
      />

      <.empty_state :if={!@visible} id="profile-closed">Perfil só para amigos.</.empty_state>

      <%= if @visible do %>
        <%= case @live_action do %>
          <% :show -> %>
            <%= for {status, {title, _}} <- @sections, @shelf[status] != [] do %>
              <.section_head id={"profile-#{status}"} title={title} count={length(@shelf[status])}>
                <:action :if={length(@shelf[status]) > @strip}>
                  <.link navigate={section_path(@owner, status)}>Ver todos</.link>
                </:action>
              </.section_head>
              <div id={"profile-#{status}-strip"} class="dk-strip dk-home-strip">
                <.profile_card
                  :for={item <- Enum.take(@shelf[status], @strip)}
                  item={mine(@mine, item)}
                  rail={status}
                  user={@user}
                  asking={@asking}
                  back={~p"/u/#{@owner.username}"}
                />
              </div>
            <% end %>

            <.empty_state
              :if={Enum.all?(@sections, fn {status, _} -> @shelf[status] == [] end)}
              id="profile-empty"
            >
              Nada jogando, zerado ou na lista.
            </.empty_state>

            <%= if @recent != [] do %>
              <.section_head id="profile-recent" title="Recente">
                <:action>
                  <.link id="profile-diary-link" navigate={~p"/u/#{@owner.username}/diario"}>
                    Ver diário
                  </.link>
                </:action>
              </.section_head>
              <div id="profile-recent-rows">
                <div
                  :for={change <- @recent}
                  id={"recent-#{change.item.game.id}"}
                  class="dk-row"
                >
                  <.poster
                    title={change.item.game.title}
                    cover_url={change.item.game.cover_url}
                    navigate={~p"/jogos/#{change.item.game.id}"}
                    size="sm"
                  />
                  <div>
                    <.link navigate={~p"/jogos/#{change.item.game.id}"} class="dk-row__title">
                      {change.item.game.title}
                    </.link>
                    <div class="dk-row__meta">
                      <b class="dk-verb">{change.verb}</b> · {relative_label(change.at)}
                    </div>
                  </div>
                  <div class="dk-row__end"></div>
                </div>
              </div>
            <% end %>
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
