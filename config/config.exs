# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :dockd, :scopes,
  user: [
    default: true,
    module: Dockd.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: Dockd.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :dockd,
  ecto_repos: [Dockd.Repo],
  generators: [timestamp_type: :utc_datetime]

# What enters the catalog from IGDB (Dockd.Catalog.Curation, documented in the README):
# a game of one of `game_types` (IGDB game_type: 0 main, 3 collection, 4 standalone
# expansion, 8 remake, 9 remaster, 10 expanded, 11 port) with a cover, popular by any
# of the counts (the rating count of the game or of the game it remasters or ports),
# published by Nintendo, among the eShop Brasil's best selling or hyped and not out yet,
# and not from a publisher in `excluded_publishers`.
config :dockd, :catalog_criteria,
  game_types: [0, 3, 4, 8, 9, 10, 11],
  min_rating_count: 50,
  min_critic_count: 5,
  min_hypes: 20,
  max_eshop_rank: 500,
  excluded_publishers: [
    "REDDEER.GAMES",
    "QubicGames",
    "HAMSTER",
    "Hamster Corporation",
    "eastasiasoft",
    "Ratalaika Games",
    "Baltoro Games",
    "Baltoro Minis",
    "Ocean Media",
    "Ultimate Games",
    "Aldora Games",
    "EpiXR Games",
    "17Studio",
    "MASK"
  ]

# Configure the endpoint
config :dockd, DockdWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DockdWeb.ErrorHTML, json: DockdWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dockd.PubSub,
  live_view: [signing_salt: "VcWMA/oS"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Mailer: the "Local" adapter keeps emails in memory, readable at "/dev/mailbox".
# Production sends by SMTP only when config/runtime.exs finds the SMTP variables;
# sign-in by link is offered only then.
config :dockd, Dockd.Mailer, adapter: Swoosh.Adapters.Local
config :dockd, :mail_from, {"Dockd", "dockd@localhost"}
config :dockd, :magic_link, true

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  dockd: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  dockd: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
