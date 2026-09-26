defmodule DockdWeb.MagicLinkLive do
  @moduledoc """
  Where a sign-in link lands: the Entrar layout with the email and one button. The link
  does not sign in by itself, so a mail scanner that opens it does not use it up.
  """
  use DockdWeb, :live_view

  alias Dockd.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      {:ok,
       assign(socket,
         page_title: "Entrar",
         form: to_form(%{"email" => user.email, "token" => token}, as: "user"),
         trigger_submit: false
       )}
    else
      {:ok,
       socket
       |> put_flash(:link_error, "Link vencido")
       |> push_navigate(to: ~p"/entrar")}
    end
  end

  @impl true
  def handle_event("submit", _params, socket),
    do: {:noreply, assign(socket, trigger_submit: true)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.form
        for={@form}
        id="magic-link-form"
        class="dk-auth"
        action={~p"/entrar"}
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
      >
        <.text_field field={@form[:email]} type="email" placeholder="E-mail" readonly />
        <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
        <button id="magic-link-submit" class="dk-btn dk-btn--primary" type="submit">Entrar</button>
      </.form>
    </Layouts.app>
    """
  end
end
