defmodule DockdWeb.CatalogReviewLive do
  @moduledoc """
  Conferir catálogo (`maquetes/edicoes.html`): what the catalog could not settle alone.
  First, Mesmo jogo?: a game and another IGDB entry, here as its own game, that may be
  the same one (`Dockd.Catalog.list_review_links/0`). Then Na eShop: the versions whose
  eShop product the daily sync could not settle, each with its candidates
  (`maquetes/casar-eshop.html`, caminho A). It is catalog data, so any account decides
  for all of them. Every answer changes its row in place, with Desfazer while the screen
  is open; the menu of the account leads here while something waits. `/eshop`, the old
  address, still opens it.
  """
  use DockdWeb, :live_view

  on_mount {DockdWeb.UserAuth, :require_authenticated}
  on_mount {DockdWeb.UserAuth, :require_admin}

  alias Dockd.{Catalog, Pricing}
  alias Dockd.Library.Shelf
  alias DockdWeb.AccountMenu

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     assign(socket,
       page_title: "Conferir catálogo",
       user: user,
       reviews: Enum.map(Catalog.list_review_links(), &review(user, &1)),
       undo: %{},
       listings: Pricing.list_review_listings(),
       prices: %{},
       errors: %{}
     )}
  end

  defp review(user, %{link: link, game: game, candidate: candidate}),
    do: %{
      link: link,
      game: Shelf.item(user, game),
      candidate: Shelf.item(user, candidate),
      state: :review
    }

  # ---------------------------------------------------------------------------
  # Mesmo jogo?

  @impl true
  def handle_event("same", %{"id" => id}, socket) do
    link = Catalog.get_game_link!(id)

    case Catalog.confirm_game_link(link) do
      {:ok, game, undo} ->
        {:noreply,
         socket
         |> put_review(id, &%{&1 | state: :same, game: Shelf.item(socket.assigns.user, game)})
         |> update(:undo, &Map.put(&1, id, undo))}

      {:error, _decided_elsewhere} ->
        {:noreply, put_decided(socket, id)}
    end
  end

  def handle_event("other", %{"id" => id}, socket) do
    case Catalog.reject_game_link(Catalog.get_game_link!(id)) do
      {:ok, link} -> {:noreply, put_review(socket, id, &%{&1 | state: :other, link: link})}
      {:error, _decided_elsewhere} -> {:noreply, put_decided(socket, id)}
    end
  end

  def handle_event("undo_same", %{"id" => id}, socket) do
    link = Catalog.get_game_link!(id)

    result =
      case {link.match, socket.assigns.undo[id]} do
        {:rejected, _} -> Catalog.reopen_game_link(link)
        {:confirmed, undo} when undo != nil -> Catalog.undo_merge(undo)
        _ -> {:error, :cannot_undo}
      end

    case result do
      {:error, _} ->
        {:noreply, update(socket, :errors, &Map.put(&1, id, "Não foi possível desfazer"))}

      _undone ->
        case Enum.find(Catalog.list_review_links(), &(&1.link.id == id)) do
          nil ->
            {:noreply, put_decided(socket, id)}

          review ->
            {:noreply,
             socket
             |> put_review(id, fn _ -> review(socket.assigns.user, review) end)
             |> update(:undo, &Map.delete(&1, id))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Na eShop

  def handle_event("choose", %{"id" => id, "external_id" => external_id}, socket) do
    listing = Pricing.get_listing!(id)

    case Pricing.confirm_listing(listing, external_id) do
      {:ok, confirmed} ->
        {:noreply, put_listing(socket, confirmed, Pricing.store_price(confirmed.release_id))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_error(socket, listing.id, "Outra versão já usa este")}

      {:error, _decided_elsewhere} ->
        {:noreply, put_listing(socket, listing, Pricing.store_price(listing.release_id))}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    listing = Pricing.get_listing!(id)

    case Pricing.reject_listing(listing) do
      {:ok, rejected} -> {:noreply, put_listing(socket, rejected, nil)}
      {:error, _decided_elsewhere} -> {:noreply, put_listing(socket, listing, nil)}
    end
  end

  def handle_event("undo", %{"id" => id}, socket) do
    listing = Pricing.get_listing!(id)

    case Pricing.reopen_listing(listing) do
      {:ok, reopened} -> {:noreply, put_listing(socket, reopened, nil)}
      {:error, _already_open} -> {:noreply, put_listing(socket, listing, nil)}
    end
  end

  defp put_review(socket, id, fun) do
    socket
    |> update(:reviews, fn reviews ->
      Enum.map(reviews, &if(&1.link.id == id, do: fun.(&1), else: &1))
    end)
    |> update(:errors, &Map.delete(&1, id))
    |> assign(:catalog_review, AccountMenu.review_count())
  end

  # Another account answered first: the row shows its answer, without Desfazer.
  defp put_decided(socket, id) do
    link = Catalog.get_game_link!(id)
    state = if link.match == :rejected, do: :other, else: :same
    put_review(socket, id, &%{&1 | state: state, link: link})
  end

  defp put_listing(socket, listing, price) do
    listing = Pricing.get_listing!(listing.id)

    socket
    |> update(:listings, fn listings ->
      Enum.map(listings, &if(&1.id == listing.id, do: listing, else: &1))
    end)
    |> update(:prices, &Map.put(&1, listing.id, price))
    |> update(:errors, &Map.delete(&1, listing.id))
    |> assign(:catalog_review, AccountMenu.review_count())
  end

  defp put_error(socket, id, message),
    do: update(socket, :errors, &Map.put(&1, id, message))

  defp open_count(items, open?), do: Enum.count(items, open?)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} catalog_review={@catalog_review}>
      <%= if @reviews != [] do %>
        <.section_head
          id="same-game-head"
          title="Mesmo jogo?"
          count={open_count(@reviews, &(&1.state == :review))}
        />
        <div id="same-game">
          <.same_game
            :for={review <- @reviews}
            id={"same-#{review.link.id}"}
            review={review}
            undo={Map.has_key?(@undo, review.link.id)}
            error={@errors[review.link.id]}
          />
        </div>
      <% end %>

      <%= if @listings != [] do %>
        <.section_head
          id="eshop-review-head"
          title="Na eShop"
          count={open_count(@listings, &(&1.match == :review))}
        />
        <div id="eshop-review">
          <.eshop_match
            :for={listing <- @listings}
            id={"match-#{listing.id}"}
            listing={listing}
            price={@prices[listing.id]}
            error={@errors[listing.id]}
          />
        </div>
      <% end %>

      <%= if @reviews == [] and @listings == [] do %>
        <.section_head id="catalog-review-head" title="Conferir catálogo" count={0} />
        <.empty_state id="catalog-review-empty">Nada para conferir.</.empty_state>
      <% end %>
    </Layouts.app>
    """
  end
end
