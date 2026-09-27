defmodule DockdWeb.AccountMenu do
  @moduledoc """
  Handles the account menu of the NavBar in every signed-in LiveView: "Copiar token da
  API" replaces the user's API token and hands the new one to the browser clipboard, and
  `@eshop_review` counts the store matches waiting in Escolher na eShop, for the item
  that leads there. A screen passes it on to `Layouts.app`.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Dockd.{Accounts, Pricing}

  def on_mount(:default, _params, _session, socket) do
    review = if socket.assigns[:current_scope], do: Pricing.review_count(), else: 0

    {:cont,
     socket
     |> assign(:eshop_review, review)
     |> attach_hook(:account_menu, :handle_event, &handle_event/3)}
  end

  defp handle_event(
         "copy_api_token",
         _params,
         %{assigns: %{current_scope: %{user: user}}} = socket
       ) do
    {:ok, token} = Accounts.create_api_token(user)
    {:halt, push_event(socket, "copy_api_token", %{token: token})}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
