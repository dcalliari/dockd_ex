import Config

config :dockd, Dockd.Repo,
  username: System.get_env("DOCKD_DB_USER", "dockd"),
  password: System.get_env("DOCKD_DB_PASSWORD", "dockd"),
  hostname: System.get_env("DOCKD_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DOCKD_DB_PORT", "5432")),
  database: System.get_env("DOCKD_DB_NAME", "dockd_e2e"),
  pool_size: 10

config :dockd, DockdWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4460],
  server: true,
  check_origin: false,
  secret_key_base:
    "e2e-secret-key-base-that-is-long-enough-for-phoenix-and-cookie-signing-0123456789"

config :dockd, :e2e, true
config :swoosh, :api_client, false
config :logger, level: :warning
