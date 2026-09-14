defmodule DockdWeb.Router do
  use DockdWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DockdWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: DockdWeb.ApiSpec
  end

  scope "/", DockdWeb do
    pipe_through :browser

    live "/", PlannerLive, :index
    live "/carteira", WalletLive, :index
    live "/biblioteca", LibraryLive, :index
    live "/catalogo", CatalogLive, :index
    live "/jogos/:id", GameLive, :show
  end

  scope "/" do
    get "/health", DockdWeb.HealthController, :show
  end

  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api/v1", DockdWeb do
    pipe_through :api

    resources "/entries", LibraryController, only: [:index, :show, :create, :update, :delete]
    resources "/ownerships", OwnershipController, only: [:index, :show, :create, :update, :delete]
    post "/releases/:release_id/price-observations", PurchasingController, :create_observation
    post "/releases/:release_id/purchases", PurchasingController, :create_purchase
    post "/releases/:release_id/vetoes", PurchasingController, :create_veto
    get "/planner", PlannerController, :show
    get "/wallet/balances", WalletController, :balances
    post "/wallet/balances", WalletController, :create_balance
    get "/wallet/reservations", WalletController, :reservations
    post "/wallet/reservations", WalletController, :create_reservation
    put "/wallet/balances/:id", WalletController, :update_balance
    delete "/wallet/balances/:id", WalletController, :delete_balance
    put "/wallet/reservations/:id", WalletController, :update_reservation
    delete "/wallet/reservations/:id", WalletController, :delete_reservation

    resources "/games", GameController, only: [:index, :show, :create, :update] do
      resources "/releases", ReleaseController, only: [:index, :show, :create, :update]
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
