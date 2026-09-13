defmodule Dockd.Repo do
  use Ecto.Repo,
    otp_app: :dockd,
    adapter: Ecto.Adapters.Postgres
end
