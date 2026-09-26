defmodule DockdWeb.SignInLive do
  @moduledoc """
  Entrar (design/maquetes/entrar.html, path C): email and password, with Criar conta and,
  when SMTP is configured, Entrar por link. The mode changes in place.

  Credentials are checked here so a wrong password shows under the field; only then the
  form posts to `UserSessionController`, which writes the session cookie.
  """
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Accounts.User

  @modes %{"password" => :password, "register" => :register, "link" => :link}

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: %User{}}}} = socket),
    do: {:ok, redirect(socket, to: ~p"/")}

  def mount(_params, _session, socket) do
    flash = socket.assigns.flash
    link_error = Phoenix.Flash.get(flash, :link_error)
    password_error = Phoenix.Flash.get(flash, :password_error)
    mode = if link_error && Accounts.magic_link_enabled?(), do: :link, else: :password

    errors =
      Enum.reject([email: link_error, password: password_error], fn {_, msg} -> is_nil(msg) end)

    {:ok,
     socket
     |> assign(
       page_title: "Entrar",
       mode: mode,
       link_enabled: Accounts.magic_link_enabled?(),
       link_sent: false,
       trigger_submit: false
     )
     |> assign_form(%{"email" => Phoenix.Flash.get(flash, :email)}, errors)}
  end

  @impl true
  def handle_event("change", %{"user" => params}, socket),
    do: {:noreply, socket |> assign(link_sent: false) |> assign_form(params, [])}

  def handle_event("mode", %{"mode" => mode}, socket) do
    mode = Map.fetch!(@modes, mode)

    if mode == :link and not socket.assigns.link_enabled do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(mode: mode, link_sent: false)
       |> assign_form(%{"email" => socket.assigns.form[:email].value}, [])}
    end
  end

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

  defp assign_form(socket, params, errors) do
    params = Map.take(params, ["email"])
    errors = for {field, msg} <- errors, do: {field, {msg, []}}
    assign(socket, form: to_form(params, as: "user", errors: errors))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.form
        for={@form}
        id="entrar-form"
        class="dk-auth"
        action={~p"/entrar"}
        phx-change="change"
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
      >
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
          <.mode_link :if={@mode == :password} id="entrar-register" mode="register">
            Criar conta
          </.mode_link>
          <.mode_link :if={@mode == :password and @link_enabled} id="entrar-link" mode="link">
            Entrar por link
          </.mode_link>
          <.mode_link :if={@mode == :register} id="entrar-password" mode="password">
            Já tenho conta
          </.mode_link>
          <.mode_link :if={@mode == :link} id="entrar-password" mode="password">
            Entrar com senha
          </.mode_link>
        </span>
      </.form>
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
