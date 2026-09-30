defmodule DockdWeb.Router do
  use DockdWeb, :router

  import DockdWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DockdWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: DockdWeb.ApiSpec
  end

  pipeline :api_user do
    plug :require_api_user
  end

  pipeline :admin do
    plug :require_admin_user
  end

  # The catalog and public profiles are public: a visitor explores them, while personal
  # data and every write need an account (see `DockdWeb.UserAuth.halt_visitor_events/2`).
  scope "/", DockdWeb do
    pipe_through :browser

    live_session :default,
      on_mount: [{DockdWeb.UserAuth, :mount_current_scope}, DockdWeb.AccountMenu] do
      live "/", HomeLive, :index
      live "/descobrir", DiscoverLive, :index
      live "/jogos/:id", GameLive, :show
      live "/sobre", AboutLive, :show
      live "/u/:username", ProfileLive, :show
      live "/u/:username/seguidores", ProfileLive, :followers
      live "/u/:username/seguindo", ProfileLive, :following
      live "/u/:username/jogando", ProfileLive, :jogando
      live "/u/:username/zerados", ProfileLive, :zerado
      live "/u/:username/quero", ProfileLive, :quero
      live "/u/:username/favoritos", ProfileLive, :favorites
      live "/u/:username/diario", ProfileLive, :diary
      live "/entrar", SignInLive, :new
      live "/criar-conta", SignInLive, :register
      live "/entrar/:token", MagicLinkLive, :new

      scope "/" do
        pipe_through :require_authenticated_user

        live "/biblioteca", LibraryLive, :index
        live "/comprar", BuyLive, :index
      end
    end

    scope "/" do
      pipe_through [:require_authenticated_user, :admin]

      live_session :admin,
        on_mount: [
          {DockdWeb.UserAuth, :mount_current_scope},
          DockdWeb.AccountMenu,
          {DockdWeb.UserAuth, :require_admin}
        ] do
        live "/conferir", CatalogReviewLive, :index
        live "/eshop", CatalogReviewLive, :index
      end
    end

    scope "/" do
      pipe_through :require_authenticated_user

      live_session :authenticated,
        on_mount: [
          {DockdWeb.UserAuth, :mount_current_scope},
          DockdWeb.AccountMenu,
          {DockdWeb.UserAuth, :require_authenticated}
        ] do
        live "/configuracoes", SettingsLive, :show
      end

      get "/configuracoes/exportar", SettingsController, :export
    end

    get "/configuracoes/email/:token", SettingsController, :confirm_email
    post "/entrar", UserSessionController, :create
    delete "/sair", UserSessionController, :delete
  end

  scope "/" do
    get "/health", DockdWeb.HealthController, :show
  end

  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api/v1", DockdWeb do
    pipe_through [:api, :api_user]

    resources "/entries", LibraryController, only: [:index, :show, :create, :update, :delete]
    resources "/ownerships", OwnershipController, only: [:index, :show, :create, :update, :delete]
    get "/purchases", PurchasingController, :index_purchases
    get "/releases/:release_id/price-observations", PurchasingController, :index_observations
    post "/releases/:release_id/price-observations", PurchasingController, :create_observation
    post "/releases/:release_id/purchases", PurchasingController, :create_purchase
    get "/vetoes", PurchasingController, :index_vetoes
    delete "/vetoes/:id", PurchasingController, :delete_veto
    post "/releases/:release_id/vetoes", PurchasingController, :create_veto
    get "/planner", PlannerController, :show
    get "/igdb/search", IGDBController, :search
    post "/igdb/games/:igdb_id/import", IGDBController, :import
    post "/igdb/sync", IGDBController, :sync
    post "/igdb/match", IGDBController, :match

    resources "/games", GameController, only: [:index, :show, :create, :update] do
      resources "/releases", ReleaseController, only: [:index, :show, :create, :update, :delete]
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:dockd, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DockdWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
