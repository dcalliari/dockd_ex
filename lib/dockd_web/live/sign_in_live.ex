defmodule DockdWeb.SignInLive do
  @moduledoc """
  Entrar and Criar conta (design/maquetes/entrar.html, path C, in the panel over covers,
  path C of design/maquetes/entrar-v2.html): email and password, with Criar conta and,
  when SMTP is configured, Entrar por link. The mode changes in place; Criar conta also has its own
  address for the NavBar. `volta` is the page to come back to after signing in.

  Credentials are checked here so a wrong password shows under the field; only then the
  form posts to `UserSessionController`, which writes the session cookie.
  """
  use DockdWeb, :live_view

  alias Dockd.{Accounts, Catalog}
  alias Dockd.Accounts.User
  alias DockdWeb.UserAuth

  # Enough covers to fill a large screen under the veil, repeating a short list.
  @wall_size 40

  @impl true
  def mount(params, _session, %{assigns: %{current_scope: %{user: %User{}}}} = socket),
    do: {:ok, redirect(socket, to: UserAuth.local_path(params["volta"]) || ~p"/")}

  def mount(params, _session, socket) do
    flash = socket.assigns.flash
    link_error = Phoenix.Flash.get(flash, :link_error)
    password_error = Phoenix.Flash.get(flash, :password_error)

    mode =
      cond do
        socket.assigns.live_action == :register -> :register
        link_error && Accounts.magic_link_enabled?() -> :link
        true -> :password
      end

    errors =
      Enum.reject([email: link_error, password: password_error], fn {_, msg} -> is_nil(msg) end)

    {:ok,
     socket
     |> assign(
       mode: mode,
       volta: UserAuth.local_path(params["volta"]),
       link_enabled: Accounts.magic_link_enabled?(),
       link_sent: false,
       trigger_submit: false,
       wall: wall()
     )
     |> assign_form(%{"email" => Phoenix.Flash.get(flash, :email)}, errors)}
  end

  # Entrar and Criar conta patch between their addresses; Entrar por link stays in place.
  @impl true
  def handle_params(_params, _uri, socket) do
    mode =
      case {socket.assigns.live_action, socket.assigns.mode} do
        {:register, _} -> :register
        {:new, :register} -> :password
        {:new, mode} -> mode
      end

    socket = if mode == socket.assigns.mode, do: socket, else: switch_mode(socket, mode)

    {:noreply, assign(socket, page_title: page_title(mode))}
  end

  @impl true
  def handle_event("change", %{"user" => params}, socket),
    do: {:noreply, socket |> assign(link_sent: false) |> assign_form(params, [])}

  def handle_event("mode", %{"mode" => "link"}, %{assigns: %{link_enabled: true}} = socket),
    do: {:noreply, switch_mode(socket, :link)}

  def handle_event("mode", %{"mode" => "password"}, socket),
    do: {:noreply, switch_mode(socket, :password)}

  def handle_event("mode", _params, socket), do: {:noreply, socket}

  def handle_event("submit", %{"user" => params}, socket),
    do: {:noreply, submit(socket.assigns.mode, params, socket)}

  defp submit(:password, %{"email" => email, "password" => password} = params, socket) do
    if Accounts.get_user_by_email_and_password(email, password) do
      assign(socket, trigger_submit: true)
    else
      assign_form(socket, params, password: "E-mail ou senha errados")
    end
  end

  defp submit(:register, params, socket) do
    case Accounts.register_user(params) do
      {:ok, _user} ->
        assign(socket, trigger_submit: true)

      {:error, changeset} ->
        errors = for {field, {msg, _}} <- changeset.errors, do: {field, msg}
        assign_form(socket, params, Enum.uniq_by(errors, &elem(&1, 0)))
    end
  end

  defp submit(:link, %{"email" => email} = params, socket) do
    changeset = Accounts.change_user_registration(%User{}, params, validate_unique: false)

    case Keyword.get(changeset.errors, :email) do
      {msg, _} ->
        assign_form(socket, params, email: msg)

      nil ->
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_login_instructions(user, &url(~p"/entrar/#{&1}"))
        end

        assign(socket, link_sent: true)
    end
  end

  # Covers of the most followed works of the year: the same list as the Em alta strip.
  defp wall do
    case :popular |> Catalog.showcase() |> Enum.filter(& &1.cover_url) do
      [] -> []
      results -> results |> Stream.cycle() |> Enum.take(@wall_size)
    end
  end

  defp switch_mode(socket, mode) do
    socket
    |> assign(mode: mode, link_sent: false)
    |> assign_form(%{"email" => socket.assigns.form[:email].value}, [])
  end

  defp page_title(:register), do: "Criar conta"
  defp page_title(_mode), do: "Entrar"

  # Criar conta and Entrar keep the email and the page to come back to.
  defp mode_path(:register, volta), do: ~p"/criar-conta?#{volta_query(volta)}"
  defp mode_path(:password, volta), do: ~p"/entrar?#{volta_query(volta)}"

  defp volta_query(nil), do: %{}
  defp volta_query(volta), do: %{volta: volta}

  defp assign_form(socket, params, errors) do
    params = Map.take(params, ["email"])
    errors = for {field, msg} <- errors, do: {field, {msg, []}}
    assign(socket, form: to_form(params, as: "user", errors: errors))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={page_title(@mode)}
      footer={false}
    >
      <:bleed>
        <div id="entrar-backdrop" class="dk-auth-backdrop">
          <div :if={@wall != []} id="entrar-wall" class="dk-auth-backdrop__wall" aria-hidden="true">
            <.poster :for={result <- @wall} title={result.title} cover_url={result.cover_url} />
          </div>
          <div class="dk-auth-panel">
            <.form
              for={@form}
              id="entrar-form"
              class="dk-auth"
              action={~p"/entrar"}
              phx-change="change"
              phx-submit="submit"
              phx-trigger-action={@trigger_submit}
            >
              <input :if={@volta} type="hidden" name="volta" value={@volta} />
              <.text_field
                field={@form[:email]}
                type="email"
                placeholder="E-mail"
                autocomplete="username"
                required
                phx-mounted={JS.focus()}
              />
              <.text_field
                :if={@mode != :link}
                field={@form[:password]}
                type="password"
                placeholder="Senha"
                autocomplete={if(@mode == :register, do: "new-password", else: "current-password")}
                required
              />
              <button
                id="entrar-submit"
                class="dk-btn dk-btn--primary"
                type="submit"
                disabled={@link_sent}
              >
                {submit_label(@mode, @link_sent)}
              </button>
              <span class="dk-auth__links">
                <.link
                  :if={@mode == :password}
                  id="entrar-register"
                  patch={mode_path(:register, @volta)}
                  class="dk-link"
                >
                  Criar conta
                </.link>
                <.mode_link :if={@mode == :password and @link_enabled} id="entrar-link" mode="link">
                  Entrar por link
                </.mode_link>
                <.link
                  :if={@mode == :register}
                  id="entrar-password"
                  patch={mode_path(:password, @volta)}
                  class="dk-link"
                >
                  Já tenho conta
                </.link>
                <.mode_link :if={@mode == :link} id="entrar-password" mode="password">
                  Entrar com senha
                </.mode_link>
              </span>
            </.form>
          </div>
        </div>
      </:bleed>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :mode, :string, required: true
  slot :inner_block, required: true

  defp mode_link(assigns) do
    ~H"""
    <button id={@id} type="button" class="dk-link" phx-click="mode" phx-value-mode={@mode}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp submit_label(:password, _), do: "Entrar"
  defp submit_label(:register, _), do: "Criar conta"
  defp submit_label(:link, false), do: "Receber link"
  defp submit_label(:link, true), do: "Link enviado"
end
