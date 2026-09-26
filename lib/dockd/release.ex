defmodule Dockd.Release do
  @moduledoc false
  @app :dockd

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Gives the library that predates accounts an email and a password. Run once after the
  migration that added accounts: `bin/dockd eval 'Dockd.Release.claim_owner("email", "senha")'`.
  """
  def claim_owner(email, password) do
    with_repo(fn -> Dockd.Accounts.claim_owner(email, password) end)
  end

  @doc ~S"""
  Replaces a forgotten password and ends the account's sessions:
  `bin/dockd eval 'Dockd.Release.reset_password("email", "senha")'`.
  """
  def reset_password(email, password) do
    with_repo(fn -> Dockd.Accounts.reset_password(email, password) end)
  end

  defp with_repo(fun) do
    load_app()
    [repo] = repos()
    {:ok, result, _} = Ecto.Migrator.with_repo(repo, fn _repo -> fun.() end)
    result
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.load(@app)
  end
end
