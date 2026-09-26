defmodule DockdWeb.UserAuth do
  @moduledoc """
  Authentication for the browser (session and remember-me cookie) and for the API
  (bearer token). Both assign `current_scope`.
  """
  use DockdWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Dockd.Accounts
  alias Dockd.Accounts.Scope

  # The remember-me cookie matches the session validity in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_dockd_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # A session token older than this is replaced on the next request, so an active
  # user is never signed out by the 14-day validity.
  @session_reissue_age_in_days 7

  @doc """
  Signs the user in, remembered on this device, and goes back to where they were headed:
  `return_to` when it is a path of this site, else the page that asked for an account.
  """
  def log_in_user(conn, user, return_to \\ nil) do
    user_return_to = local_path(return_to) || get_session(conn, :user_return_to)

    conn
    |> create_or_extend_session(user)
    |> delete_session(:user_return_to)
    |> redirect(to: user_return_to || ~p"/")
  end

  @doc "Signs the user out, clearing the session, the cookie and open LiveViews."
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      DockdWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  @doc "Entrar, coming back to `return_to` afterwards."
  def sign_in_path(nil), do: ~p"/entrar"
  def sign_in_path(return_to), do: ~p"/entrar?#{%{volta: return_to}}"

  @doc "`path` when it is a path of this site, never another host; nil otherwise."
  def local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: nil, else: path
  end

  def local_path(_), do: nil

  @doc "Assigns `current_scope` from the session or the remember-me cookie."
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      end
    end
  end

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user)
    else
      conn
    end
  end

  defp create_or_extend_session(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  # Extending the session of the same user keeps it, so open tabs keep their CSRF token.
  defp renew_session(conn, user) when conn.assigns.current_scope.user.id == user.id, do: conn

  # A new sign-in or a sign-out gets a new session id, against session fixation.
  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc "Disconnects the LiveViews opened with the given tokens."
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      DockdWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  LiveView `on_mount`:

    * `:mount_current_scope` assigns `current_scope`, nil when signed out.
    * `:require_authenticated` also sends a signed-out visitor to Entrar.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/entrar")}
    end
  end

  @doc """
  Public screens show a visitor everything but save nothing: every event outside
  `allowed` is dropped before the LiveView sees it.
  """
  def halt_visitor_events(%{assigns: %{current_scope: %Scope{}}} = socket, _allowed), do: socket

  def halt_visitor_events(socket, allowed) do
    Phoenix.LiveView.attach_hook(socket, :visitor_events, :handle_event, fn event, _, socket ->
      if event in allowed, do: {:cont, socket}, else: {:halt, socket}
    end)
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      {user, _} =
        if user_token = session["user_token"] do
          Accounts.get_user_by_session_token(user_token)
        end || {nil, nil}

      Scope.for_user(user)
    end)
  end

  @doc "Plug that sends a signed-out visitor to Entrar, remembering the page."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> redirect(to: ~p"/entrar")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, :user_return_to, current_path(conn))

  defp maybe_store_return_to(conn), do: conn

  @doc "API plug: authenticates `Authorization: Bearer <token>` or answers 401."
  def require_api_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Accounts.User{} = user <- Accounts.get_user_by_api_token(String.trim(token)) do
      assign(conn, :current_scope, Scope.for_user(user))
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: %{detail: "Unauthorized"}})
        |> halt()
    end
  end
end
