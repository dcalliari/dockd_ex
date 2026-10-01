defmodule DockdWeb.SettingsLive do
  @moduledoc """
  The account settings page. Each change is saved in place, while the destructive
  account deletion confirmation stays in the app instead of using a browser dialog.
  """
  use DockdWeb, :live_view

  alias Dockd.Accounts
  alias Dockd.Accounts.Scope
  alias Dockd.Social
  alias DockdWeb.UserAuth

  @delete_confirmation "EXCLUIR"

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(
       user: user,
       current_token: session["user_token"],
       sessions: Accounts.list_user_sessions(user),
       editing: nil,
       profile_notice: nil,
       email_notice: nil,
       password_notice: nil,
       session_notice: nil,
       delete_open: false,
       page_title: "Configurações"
     )
     |> assign_forms(user)}
  end

  @impl true
  def handle_event("edit", %{"section" => "email"}, socket),
    do: {:noreply, assign(socket, editing: :email)}

  def handle_event("edit", %{"section" => "password"}, socket),
    do: {:noreply, assign(socket, editing: :password)}

  def handle_event("edit", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(editing: nil) |> assign_forms(socket.assigns.user)}
  end

  def handle_event("validate_profile", %{"user" => params}, socket) do
    changeset = Accounts.change_user_profile(socket.assigns.user, params, validate_unique: false)
    {:noreply, assign(socket, profile_form: to_form(changeset, action: :validate))}
  end

  def handle_event("save_profile", %{"user" => params}, socket) do
    case Accounts.update_user_profile(socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_user(user)
         |> assign(profile_notice: "Perfil atualizado")
         |> assign_forms(user)}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset, action: :validate))}
    end
  end

  def handle_event("validate_email", %{"email" => params}, socket) do
    changeset = Accounts.change_user_email(socket.assigns.user, params, validate_unique: false)
    {:noreply, assign(socket, email_form: to_form(changeset, as: :email, action: :validate))}
  end

  def handle_event("save_email", %{"email" => params}, socket) do
    user = socket.assigns.user

    case Accounts.deliver_user_email_change_instructions(
           user,
           params,
           &url(~p"/configuracoes/email/#{&1}")
         ) do
      {:ok, _email} ->
        {:noreply,
         socket
         |> assign(editing: nil, email_notice: "Confirmação enviada")
         |> assign(email_form: email_form())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, email_form: to_form(changeset, as: :email, action: :validate))}

      {:error, :magic_link_disabled} ->
        {:noreply,
         assign(socket,
           email_form: form_with_errors(%{}, :email, email: "Envio de e-mail indisponível")
         )}
    end
  end

  def handle_event("validate_password", %{"password" => params}, socket) do
    {:noreply, assign(socket, password_form: password_form(socket.assigns.user, params, true))}
  end

  def handle_event("save_password", %{"password" => params}, socket) do
    user = socket.assigns.user
    form = password_form(user, params, true)

    if form.errors == [] do
      case Accounts.update_user_password_with_current(
             user,
             Map.get(params, "current_password", ""),
             %{password: Map.get(params, "new_password", "")},
             socket.assigns.current_token
           ) do
        {:ok, {user, tokens}} ->
          UserAuth.disconnect_sessions(tokens)

          {:noreply,
           socket
           |> put_user(user)
           |> assign(editing: nil, password_notice: "Senha atualizada")
           |> assign(password_form: password_form(user, %{}, false))}

        {:error, :current_password} ->
          {:noreply,
           assign(
             socket,
             password_form:
               form_with_errors(params, :password, current_password: "Senha atual incorreta")
           )}

        {:error, changeset} ->
          {:noreply,
           assign(socket, password_form: password_form_from_changeset(params, changeset))}
      end
    else
      {:noreply, assign(socket, password_form: form)}
    end
  end

  def handle_event("set_visibility", %{"visibility" => visibility}, socket) do
    {:ok, user} = Social.set_visibility(socket.assigns.user, visibility)
    {:noreply, put_user(socket, user)}
  end

  def handle_event("end_other_sessions", _params, socket) do
    tokens =
      Accounts.delete_other_user_sessions(socket.assigns.user, socket.assigns.current_token)

    UserAuth.disconnect_sessions(tokens)

    {:noreply,
     socket
     |> assign(sessions: Accounts.list_user_sessions(socket.assigns.user))
     |> assign(session_notice: "Outras sessões encerradas")}
  end

  def handle_event("open_delete", _params, socket),
    do: {:noreply, assign(socket, delete_open: true)}

  def handle_event("close_delete", _params, socket) do
    {:noreply, socket |> assign(delete_open: false) |> assign(delete_form: delete_form())}
  end

  def handle_event("delete_account", %{"delete" => params}, socket) do
    if Map.get(params, "confirmation") == @delete_confirmation do
      {:ok, tokens} = Accounts.delete_user(socket.assigns.user)
      UserAuth.disconnect_sessions(tokens)
      {:noreply, push_navigate(socket, to: ~p"/")}
    else
      {:noreply,
       assign(
         socket,
         delete_form:
           form_with_errors(params, :delete, confirmation: "Digite EXCLUIR para continuar")
       )}
    end
  end

  defp put_user(socket, user), do: assign(socket, user: user, current_scope: Scope.for_user(user))

  defp assign_forms(socket, user) do
    assign(socket,
      profile_form: to_form(Accounts.change_user_profile(user)),
      email_form: email_form(),
      password_form: password_form(user, %{}, false),
      delete_form: delete_form()
    )
  end

  defp email_form, do: to_form(%{}, as: :email)
  defp delete_form, do: to_form(%{}, as: :delete)

  defp password_form(_user, params, false), do: to_form(params, as: :password)

  defp password_form(user, params, true) do
    changeset =
      Accounts.change_user_password(user, %{password: Map.get(params, "new_password", "")})

    errors =
      if Map.get(params, "confirmation", "") != Map.get(params, "new_password", "") do
        [confirmation: "As senhas não conferem"]
      else
        []
      end

    password_form_from_changeset(params, %{changeset | errors: errors ++ changeset.errors})
  end

  defp password_form_from_changeset(params, changeset) do
    errors =
      for {field, {message, options}} <- changeset.errors do
        field = if field == :password, do: :new_password, else: field
        {field, {message, options}}
      end

    to_form(params, as: :password, errors: errors)
  end

  defp form_with_errors(params, as, errors) do
    errors = for {field, message} <- errors, do: {field, {message, []}}
    to_form(params, as: as, errors: errors)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      catalog_review={@catalog_review}
      current="Configurações"
    >
      <p class="dk-back">
        <.link id="settings-profile-link" navigate={~p"/u/#{@user.username}"} class="dk-link">
          <.icon name="hero-arrow-left" /> Ver perfil
        </.link>
      </p>

      <nav id="settings-sections" class="dk-settings-nav" aria-label="Configurações">
        <a href="#settings-profile">Perfil</a>
        <a href="#settings-access">Acesso</a>
        <a href="#settings-data">Dados</a>
      </nav>

      <section id="settings-profile" class="dk-settings-section">
        <.section_head title="Perfil">
          <:action><.link navigate={~p"/u/#{@user.username}"}>Ver perfil</.link></:action>
        </.section_head>
        <.form
          for={@profile_form}
          id="settings-profile-form"
          class="dk-settings-form"
          phx-change="validate_profile"
          phx-submit="save_profile"
        >
          <.text_field
            field={@profile_form[:name]}
            placeholder="Nome de exibição"
            autocomplete="name"
            required
          />
          <.text_field
            field={@profile_form[:username]}
            placeholder="Usuário"
            autocomplete="username"
            required
          />
          <.text_field field={@profile_form[:bio]} placeholder="Bio curta" maxlength="140" />
          <.text_field field={@profile_form[:location]} placeholder="Local" maxlength="60" />
          <.text_field
            field={@profile_form[:link]}
            placeholder="Link"
            autocomplete="url"
            maxlength="200"
          />
          <div class="dk-settings-form__actions">
            <button id="settings-profile-submit" class="dk-btn dk-btn--primary" type="submit">Atualizar perfil</button>
            <span :if={@profile_notice} id="settings-profile-notice" class="dk-settings-notice">{@profile_notice}</span>
          </div>
        </.form>

        <div class="dk-settings-row">
          <div>
            <b>Quem vê seu perfil</b><small>Seu perfil está {if(@user.profile_visibility == :public,
              do: "público",
              else: "só para amigos"
            )}</small>
          </div>
          <.visibility_choice id="settings-visibility" visibility={@user.profile_visibility} />
        </div>
      </section>

      <section id="settings-access" class="dk-settings-section">
        <.section_head title="Acesso" />
        <div class="dk-settings-row">
          <div><b>E-mail</b><small>{@user.email}</small></div>
          <button
            id="settings-edit-email"
            class="dk-btn dk-btn--secondary dk-btn--sm"
            type="button"
            phx-click="edit"
            phx-value-section="email"
          >Trocar e-mail</button>
        </div>
        <.form
          :if={@editing == :email}
          for={@email_form}
          id="settings-email-form"
          class="dk-settings-form dk-settings-form--inline"
          phx-change="validate_email"
          phx-submit="save_email"
        >
          <.text_field
            field={@email_form[:email]}
            type="email"
            placeholder="Novo e-mail"
            autocomplete="email"
            required
          />
          <div class="dk-settings-form__actions">
            <button id="settings-email-submit" class="dk-btn dk-btn--primary" type="submit">Enviar confirmação</button>
            <button class="dk-link" type="button" phx-click="cancel_edit">Cancelar</button>
          </div>
        </.form>
        <p :if={@email_notice} id="settings-email-notice" class="dk-settings-notice">
          {@email_notice}
        </p>

        <div class="dk-settings-row">
          <div><b>Senha</b><small>Peça sua senha atual</small></div>
          <button
            id="settings-edit-password"
            class="dk-btn dk-btn--secondary dk-btn--sm"
            type="button"
            phx-click="edit"
            phx-value-section="password"
          >Trocar senha</button>
        </div>
        <.form
          :if={@editing == :password}
          for={@password_form}
          id="settings-password-form"
          class="dk-settings-form dk-settings-form--inline"
          phx-change="validate_password"
          phx-submit="save_password"
        >
          <.text_field
            field={@password_form[:current_password]}
            type="password"
            placeholder="Senha atual"
            autocomplete="current-password"
            required
          />
          <.text_field
            field={@password_form[:new_password]}
            type="password"
            placeholder="Senha nova"
            autocomplete="new-password"
            required
          />
          <.text_field
            field={@password_form[:confirmation]}
            type="password"
            placeholder="Repita a senha"
            autocomplete="new-password"
            required
          />
          <div class="dk-settings-form__actions">
            <button id="settings-password-submit" class="dk-btn dk-btn--primary" type="submit">Atualizar senha</button>
            <button class="dk-link" type="button" phx-click="cancel_edit">Cancelar</button>
          </div>
        </.form>
        <p :if={@password_notice} id="settings-password-notice" class="dk-settings-notice">
          {@password_notice}
        </p>

        <div class="dk-settings-row">
          <div>
            <b>Sessões ativas</b><small>{length(@sessions)} sessão{if(length(@sessions) == 1,
              do: "",
              else: "ões"
            )}</small>
          </div>
          <button
            id="settings-end-sessions"
            class="dk-btn dk-btn--secondary dk-btn--sm"
            type="button"
            phx-click="end_other_sessions"
          >Sair dos outros</button>
        </div>
        <p :if={@session_notice} id="settings-session-notice" class="dk-settings-notice">
          {@session_notice}
        </p>
      </section>

      <section id="settings-data" class="dk-settings-section dk-settings-section--danger">
        <.section_head title="Seus dados" />
        <div class="dk-settings-row">
          <div><b>Baixar meus dados</b><small>Biblioteca, compras e histórico</small></div>
          <a
            id="settings-export"
            class="dk-btn dk-btn--secondary dk-btn--sm"
            href={~p"/configuracoes/exportar"}
          >Exportar dados</a>
        </div>
        <div class="dk-settings-row">
          <div><b>Excluir conta</b><small>Esta ação não pode ser desfeita</small></div>
          <button
            id="settings-delete"
            class="dk-btn dk-btn--secondary dk-btn--sm"
            type="button"
            phx-click="open_delete"
          >Excluir conta</button>
        </div>
      </section>

      <div :if={@delete_open} id="settings-delete-modal" class="dk-modal" role="presentation">
        <section
          class="dk-modal__panel"
          role="dialog"
          aria-modal="true"
          aria-labelledby="settings-delete-title"
        >
          <h2 id="settings-delete-title">Excluir conta</h2>
          <p>Digite EXCLUIR para apagar sua conta e todos os seus dados.</p>
          <.form
            for={@delete_form}
            id="settings-delete-form"
            class="dk-settings-form"
            phx-submit="delete_account"
          >
            <.text_field
              field={@delete_form[:confirmation]}
              placeholder="Digite EXCLUIR"
              autocomplete="off"
              required
            />
            <div class="dk-settings-form__actions">
              <button id="settings-delete-submit" class="dk-btn dk-btn--primary" type="submit">Excluir conta</button>
              <button
                id="settings-delete-cancel"
                class="dk-link"
                type="button"
                phx-click="close_delete"
              >Cancelar</button>
            </div>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
