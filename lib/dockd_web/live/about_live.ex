defmodule DockdWeb.AboutLive do
  @moduledoc """
  Sobre, reached from the footer: what Dockd is in three sentences and the IGDB credit.
  Public, like the catalog.
  """
  use DockdWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Sobre")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} catalog_review={@catalog_review}>
      <div id="about" class="dk-about">
        <p>
          dockd. é uma biblioteca pessoal de jogos de Switch e Switch 2.
          Guarda o que você tem, o que quer, o que está jogando e o que vai comprar.
          Cada preço aparece com a data em que foi visto.
        </p>
      </div>
    </Layouts.app>
    """
  end
end
