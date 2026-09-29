defmodule Dockd.Library.Shelf do
  @moduledoc """
  Read model of a user's library: one item per game with a single derived status.

  The status is derived, never stored (ADR-0004 keeps intention and ownership as
  independent axes):

    * `:jogando` when the entry is playing, `:pausado` when paused
    * `:zerado` when finished, `:larguei` when abandoned
    * `:backlog` when the user owns at least one release and has not started
    * `:quero` when there is no ownership and the purchase intent is want, planned or preordered
    * `nil` otherwise (a game the user only browsed)

  Pausado shares the Jogando tab (`tab_key/1`): it is still being played, just not
  right now. Jogando, Pausado, Zerado and Larguei all require ownership, the same as
  Backlog (`Dockd.Library.set_status/4`); `owned?` here only reflects that gate, not
  whether it renders.
  """
  import Ecto.Query
  alias Dockd.Accounts.User
  alias Dockd.Catalog.Game
  alias Dockd.Library.{Entry, Ownership}
  alias Dockd.Repo

  @statuses [:quero, :backlog, :jogando, :pausado, :zerado, :larguei]
  @tabs ~w(todos jogando backlog quero zerado)
  @wanting [:want, :planned, :preordered]

  defstruct [:game, :entry, :status, :platforms, :year, ownerships: [], releases: []]

  @doc "The six statuses, in display order."
  def statuses, do: @statuses

  @doc "Biblioteca tabs in display order."
  def tabs, do: @tabs

  @doc "Derives the status from an entry (or nil) and whether any release is owned."
  def status(entry, owned?)
  def status(%Entry{play_state: :playing}, _), do: :jogando
  def status(%Entry{play_state: :paused}, _), do: :pausado
  def status(%Entry{play_state: :finished}, _), do: :zerado
  def status(%Entry{play_state: :abandoned}, _), do: :larguei
  def status(_entry, true), do: :backlog
  def status(%Entry{purchase_intent: intent}, false) when intent in @wanting, do: :quero
  def status(_entry, _owned?), do: nil

  @doc "The tab a status counts and filters under; Pausado shares Jogando's."
  def tab_key(:pausado), do: "jogando"
  def tab_key(status), do: Atom.to_string(status)

  @doc "Lists every game the user has a relation with, one item per game."
  def list(%User{id: user_id}) do
    entries =
      Repo.all(from e in Entry, where: e.user_id == ^user_id, preload: [game: :releases])

    ownerships =
      Repo.all(
        from o in Ownership,
          where: o.user_id == ^user_id,
          preload: [release: [game: :releases]]
      )

    owned_by_game = Enum.group_by(ownerships, & &1.release.game_id)
    entries_by_game = Map.new(entries, &{&1.game_id, &1})

    games =
      Map.new(entries, &{&1.game_id, &1.game})
      |> Map.merge(Map.new(ownerships, &{&1.release.game_id, &1.release.game}))

    games
    |> Enum.map(fn {game_id, game} ->
      build(game, entries_by_game[game_id], Map.get(owned_by_game, game_id, []))
    end)
    |> Enum.reject(&is_nil(&1.status))
    |> Enum.sort_by(&String.downcase(&1.game.title))
  end

  @doc "Builds the shelf item of one game for a user."
  def item(nil, %Game{} = game), do: build(Repo.preload(game, :releases), nil, [])

  def item(%User{id: user_id}, %Game{} = game) do
    game = Repo.preload(game, :releases)
    entry = Repo.one(from e in Entry, where: e.user_id == ^user_id and e.game_id == ^game.id)

    ownerships =
      Repo.all(
        from o in Ownership,
          join: r in assoc(o, :release),
          where: o.user_id == ^user_id and r.game_id == ^game.id,
          preload: [release: r]
      )

    build(game, entry, ownerships)
  end

  defp build(game, entry, ownerships) do
    releases = game.releases || []

    %__MODULE__{
      game: game,
      entry: entry,
      ownerships: ownerships,
      releases: releases,
      status: status(entry, ownerships != []),
      platforms: releases |> Enum.map(& &1.platform) |> Enum.uniq() |> Enum.sort(),
      year: releases |> Enum.map(& &1.release_date) |> Enum.reject(&is_nil/1) |> earliest_year()
    }
  end

  defp earliest_year([]), do: nil
  defp earliest_year(dates), do: dates |> Enum.min(Date) |> Map.fetch!(:year)

  @doc "Counts items per tab, `todos` included."
  def counts(items) do
    base = Map.new(@tabs, &{&1, 0})

    Enum.reduce(items, %{base | "todos" => length(items)}, fn item, acc ->
      Map.update(acc, tab_key(item.status), 1, &(&1 + 1))
    end)
  end

  @doc """
  Filters and sorts items by the Biblioteca controls.

  Keys: `"tab"`, `"plat"` (switch or switch_2), `"media"` (physical or digital)
  and `"sort"` (`titulo` or `lancamento`). Title search lives in Descobrir.
  """
  def filter(items, params) do
    tab = Map.get(params, "tab", "todos")
    plat = Map.get(params, "plat", "")
    media = Map.get(params, "media", "")

    items
    |> Enum.filter(fn item ->
      (tab in ["", "todos"] or tab_key(item.status) == tab) and
        (plat == "" or plat in Enum.map(item.platforms, &Atom.to_string/1)) and
        (media == "" or Enum.any?(item.ownerships, &(Atom.to_string(&1.ownership_type) == media)))
    end)
    |> sort(Map.get(params, "sort", "titulo"))
  end

  defp sort(items, "lancamento"),
    do: Enum.sort_by(items, &{-(&1.year || 0), String.downcase(&1.game.title)})

  defp sort(items, _), do: items

  @doc "The release out first; undated releases come last."
  def first_release(%__MODULE__{releases: releases}),
    do:
      Enum.min_by(releases, &{is_nil(&1.release_date), &1.release_date}, &first?/2, fn -> nil end)

  defp first?({same, a}, {same, b}) when not is_nil(a), do: Date.compare(a, b) != :gt
  defp first?({undated_a, _}, {undated_b, _}), do: undated_a <= undated_b

  @doc "Media types the user owns for the item."
  def media(%__MODULE__{ownerships: ownerships}),
    do: ownerships |> Enum.map(& &1.ownership_type) |> Enum.uniq()
end
