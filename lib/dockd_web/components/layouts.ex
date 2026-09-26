defmodule DockdWeb.Layouts do
  @moduledoc """
  Application shell: top navigation, page container, bottom navigation on phones,
  IGDB attribution and flash messages. Signed out, only the wordmark remains.
  """
  use DockdWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current, :string, default: nil, doc: "Biblioteca, Comprar or Descobrir"
  attr :search, :string, default: ""
  attr :search_live, :boolean, default: false
  attr :current_scope, :map, default: nil
  attr :igdb_url, :string, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.nav_bar
      current_scope={@current_scope}
      current={@current}
      search={@search}
      search_live={@search_live}
    />
    <main class="dk-page">
      {render_slot(@inner_block)}
      <p :if={@current_scope} class="dk-credit">
        Dados de jogos por
        <a href="https://www.igdb.com" target="_blank" rel="noopener noreferrer">IGDB</a>
        <span :if={@igdb_url}>
          · <a href={@igdb_url} target="_blank" rel="noopener noreferrer">Mais informações no IGDB</a>
        </span>
      </p>
    </main>
    <.bottom_nav :if={@current_scope} current={@current} />
    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Sem conexão. Tentando de novo.
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Algo deu errado. Tentando de novo.
      </.flash>
    </div>
    """
  end
end
