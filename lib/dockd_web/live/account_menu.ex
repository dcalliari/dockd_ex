defmodule DockdWeb.AccountMenu do
  @moduledoc """
  Handles the account menu of the NavBar in every signed-in LiveView: "Copiar token da
  API" replaces the user's API token and hands the new one to the browser clipboard.
  """
  import Phoenix.LiveView

  alias Dockd.Accounts

  def on_mount(:default, _params, _session, socket),
    do: {:cont, attach_hook(socket, :account_menu, :handle_event, &handle_event/3)}

  defp handle_event("copy_api_token", _params, socket) do
    {:ok, token} = Accounts.create_api_token(socket.assigns.current_scope.user)
    {:halt, push_event(socket, "copy_api_token", %{token: token})}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
