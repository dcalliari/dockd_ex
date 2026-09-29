defmodule DockdWeb.SettingsLive do
  @moduledoc """
  Configurações da conta em `/configuracoes` (design/maquetes/configuracoes.html, opção
  A): Perfil (nome de exibição, nome de usuário, privacidade), Conta (e-mail, senha) e
  Encerrar (excluir conta), em três SectionHead na mesma rolagem. Aberta pelo item
  Configurações do menu da conta, logo depois de Perfil.

  Nome, nome de usuário e privacidade gravam ao sair do campo, sem botão. Trocar e-mail e
  excluir a conta confirmam dentro do próprio controle, nunca em `confirm()`, e as duas
  acabam a sessão: a próxima tela é Entrar.
  """
  use DockdWeb, :live_view

  alias Dockd.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(page_title: "Configurações", user: user)
     |> assign(name_form: to_form(Accounts.change_user_name(user), as: "user"))
     |> assign(username_form: to_form(Accounts.change_user_username(user), as: "user"))
     |> assign(email_editing: false, email_form: email_form(user))
     |> assign(password_form: to_form(Accounts.change_user_password(user), as: "user"))
     |> assign(delete_confirming: false)}
  end

  @impl true
  def handle_event("save_name", %{"user" => params}, socket) do
    case Accounts.update_user_name(socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         assign(socket,
           user: user,
           name_form: to_form(Accounts.change_user_name(user), as: "user")
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, name_form: to_form(changeset, as: "user", action: :insert))}
    end
  end

  def handle_event("save_username", %{"user" => params}, socket) do
    case Accounts.update_user_username(socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         assign(socket,
           user: user,
           username_form: to_form(Accounts.change_user_username(user), as: "user")
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, username_form: to_form(changeset, as: "user", action: :insert))}
    end
  end

  def handle_event("set_visibility", %{"visibility" => visibility}, socket) do
    {:ok, user} = Dockd.Social.set_visibility(socket.assigns.user, visibility)
    {:noreply, assign(socket, user: user)}
  end

  def handle_event("edit_email", _params, socket) do
    {:noreply, assign(socket, email_editing: true, email_form: email_form(socket.assigns.user))}
  end

  def handle_event("cancel_email", _params, socket) do
    {:noreply, assign(socket, email_editing: false, email_form: email_form(socket.assigns.user))}
  end

  def handle_event("change_email", %{"user" => params}, socket) do
    changeset = Accounts.change_user_email(socket.assigns.user, Map.take(params, ["email"]))
    {:noreply, assign_email_form(socket, params, changeset_errors(changeset))}
  end

  def handle_event("save_email", %{"user" => params}, socket) do
    %{"email" => email, "current_password" => password} = params

    case Accounts.update_user_email(socket.assigns.user, password, %{email: email}) do
      {:ok, {_user, _expired}} ->
        {:noreply,
         socket
         |> put_flash(:info, "E-mail trocado. Entre de novo.")
         |> redirect(to: ~p"/entrar")}

      {:error, :invalid_password} ->
        {:noreply, assign_email_form(socket, params, current_password: "Senha atual errada")}

      {:error, changeset} ->
        {:noreply, assign_email_form(socket, params, changeset_errors(changeset))}
    end
  end

  def handle_event("save_password", %{"user" => params}, socket) do
    case Accounts.update_user_password(socket.assigns.user, params) do
      {:ok, {_user, _expired}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Senha trocada. Entre de novo.")
         |> redirect(to: ~p"/entrar")}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, as: "user", action: :insert))}
    end
  end

  def handle_event("confirm_delete", _params, socket),
    do: {:noreply, assign(socket, delete_confirming: true)}

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, delete_confirming: false)}

  def handle_event("delete_account", _params, socket) do
    {:ok, _user} = Accounts.delete_user(socket.assigns.user)

    {:noreply,
     socket
     |> put_flash(:info, "Conta excluída.")
     |> redirect(to: ~p"/")}
  end

  defp email_form(user), do: to_form(%{"email" => user.email}, as: "user")

  defp assign_email_form(socket, params, errors) do
    errors = for {field, msg} <- errors, do: {field, {msg, []}}

    assign(socket,
      email_form:
        to_form(Map.take(params, ["email", "current_password"]), as: "user", errors: errors)
    )
  end

  defp changeset_errors(changeset),
    do: for({field, {msg, _}} <- changeset.errors, do: {field, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} catalog_review={@catalog_review}>
      <.section_head id="settings-perfil" title="Perfil" />
      <.form for={@name_form} id="settings-name-form" phx-change="save_name">
        <.settings_row label="Nome de exibição">
          <.text_field field={@name_form[:name]} placeholder="Nome de exibição" phx-debounce="blur" />
        </.settings_row>
      </.form>
      <.form for={@username_form} id="settings-username-form" phx-change="save_username">
        <.settings_row label="Nome de usuário">
          <.text_field
            field={@username_form[:username]}
            placeholder="Nome de usuário"
            phx-debounce="blur"
          />
        </.settings_row>
      </.form>
      <.settings_row label="Privacidade do perfil">
        <.visibility_choice id="settings-visibility" visibility={@user.profile_visibility} />
      </.settings_row>

      <.section_head id="settings-conta" title="Conta" />
      <.settings_row :if={!@email_editing} label="E-mail">
        <span class="dk-settings-row__value">{@user.email}</span>
        <button
          id="settings-email-edit"
          type="button"
          class="dk-btn dk-btn--secondary dk-btn--sm"
          phx-click="edit_email"
        >
          Trocar e-mail
        </button>
      </.settings_row>
      <.form
        :if={@email_editing}
        for={@email_form}
        id="settings-email-form"
        phx-change="change_email"
        phx-submit="save_email"
      >
        <.settings_row id="settings-email-confirm" label="Trocar e-mail" confirm>
          <.text_field field={@email_form[:email]} type="email" placeholder="Novo e-mail" required />
          <.text_field
            field={@email_form[:current_password]}
            type="password"
            placeholder="Senha atual"
            autocomplete="current-password"
            required
          />
          <button
            id="settings-email-cancel"
            type="button"
            class="dk-btn dk-btn--secondary dk-btn--sm"
            phx-click="cancel_email"
          >
            Cancelar
          </button>
          <button
            id="settings-email-confirm-submit"
            type="submit"
            class="dk-btn dk-btn--primary dk-btn--sm"
          >
            Confirmar troca
          </button>
        </.settings_row>
      </.form>

      <.form for={@password_form} id="settings-password-form" phx-submit="save_password">
        <.settings_row label="Senha">
          <.text_field
            field={@password_form[:password]}
            type="password"
            placeholder="Senha nova"
            autocomplete="new-password"
            required
          />
          <button
            id="settings-password-submit"
            type="submit"
            class="dk-btn dk-btn--secondary dk-btn--sm"
          >
            Trocar senha
          </button>
        </.settings_row>
      </.form>

      <.section_head id="settings-encerrar" title="Encerrar" />
      <.settings_row :if={!@delete_confirming} label="Excluir conta">
        <button
          id="settings-delete-confirm"
          type="button"
          class="dk-btn dk-btn--secondary dk-btn--sm"
          phx-click="confirm_delete"
        >
          Excluir conta
        </button>
      </.settings_row>
      <.settings_row
        :if={@delete_confirming}
        id="settings-delete-warning"
        label="Excluir conta"
        confirm
      >
        <span class="dk-settings-row__warn">Apaga biblioteca, compras e histórico para sempre.</span>
        <button
          id="settings-delete-cancel"
          type="button"
          class="dk-btn dk-btn--secondary dk-btn--sm"
          phx-click="cancel_delete"
        >
          Cancelar
        </button>
        <button
          id="settings-delete-submit"
          type="button"
          class="dk-btn dk-btn--primary dk-btn--sm"
          phx-click="delete_account"
        >
          Excluir para sempre
        </button>
      </.settings_row>
    </Layouts.app>
    """
  end
end
