defmodule DockdWeb.Showcase do
  @moduledoc """
  The visitor's home page (design/maquetes/area-publica.html, path B): three strips of
  covers from the catalog, each opening its Descobrir list. No slogan, no personal data.
  """
  use DockdWeb, :html

  alias Dockd.Catalog
  alias DockdWeb.DiscoverLive

  @per_strip 7

  @doc "The strips as `{lista, title, results}`, in the order of `DiscoverLive.lists/0`."
  def strips do
    for {lista, list, title} <- DiscoverLive.lists(),
        do: {lista, title, list |> Catalog.showcase() |> Enum.take(@per_strip)}
  end

  attr :strips, :list, required: true

  def showcase(assigns) do
    ~H"""
    <%= for {lista, title, results} <- @strips, results != [] do %>
      <.section_head id={"showcase-#{lista}"} title={title}>
        <:action>
          <.link navigate={DiscoverLive.list_path(lista, %{})}>Ver todos</.link>
        </:action>
      </.section_head>
      <div id={"strip-#{lista}"} class="dk-strip">
        <div
          :for={result <- results}
          id={"#{lista}-#{DiscoverLive.result_id(result)}"}
          class="dk-card"
        >
          <.poster
            title={result.title}
            cover_url={result.cover_url}
            navigate={~p"/jogos/#{result.game.id}"}
          />
          <.status_link back={DiscoverLive.list_path(lista, %{abrir: DiscoverLive.result_id(result)})} />
          <span class="dk-card__text">
            <span class="dk-card__title">{result.title}</span>
            <span class="dk-card__meta">{DiscoverLive.result_meta(result)}</span>
          </span>
        </div>
      </div>
    <% end %>
    """
  end
end
