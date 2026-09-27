defmodule DockdWeb.EshopReviewLive do
  @moduledoc """
  Escolher na eShop (`maquetes/casar-eshop.html`, caminho A): the versions whose eShop
  product the daily sync could not settle, each with its candidates. The store listing is
  catalog data, so any account decides for all of them. Choosing, rejecting and undoing
  change the row in place; the menu of the account leads here while something waits.
  """
  use DockdWeb, :live_view

  on_mount {DockdWeb.UserAuth, :require_authenticated}

  alias Dockd.Pricing

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Escolher na eShop",
       listings: Pricing.list_review_listings(),
       prices: %{},
       errors: %{}
     )}
  end

  @impl true
  def handle_event("choose", %{"id" => id, "external_id" => external_id}, socket) do
    listing = Pricing.get_listing!(id)

    case Pricing.confirm_listing(listing, external_id) do
      {:ok, confirmed} ->
        {:noreply, put_listing(socket, confirmed, Pricing.store_price(confirmed.release_id))}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_error(socket, listing, "Outra versão já usa este")}

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

  defp put_listing(socket, listing, price) do
    listing = Pricing.get_listing!(listing.id)

    socket
    |> update(:listings, fn listings ->
      Enum.map(listings, &if(&1.id == listing.id, do: listing, else: &1))
    end)
    |> update(:prices, &Map.put(&1, listing.id, price))
    |> update(:errors, &Map.delete(&1, listing.id))
    |> assign(:eshop_review, Pricing.review_count())
  end

  defp put_error(socket, listing, message),
    do: update(socket, :errors, &Map.put(&1, listing.id, message))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} eshop_review={@eshop_review}>
      <.section_head id="eshop-review-head" title="Escolher na eShop" count={@eshop_review} />
      <div id="eshop-review">
        <.eshop_match
          :for={listing <- @listings}
          id={"match-#{listing.id}"}
          listing={listing}
          price={@prices[listing.id]}
          error={@errors[listing.id]}
        />
      </div>
      <.empty_state :if={@listings == []} id="eshop-review-empty">
        Nada para escolher na eShop.
      </.empty_state>
    </Layouts.app>
    """
  end
end
