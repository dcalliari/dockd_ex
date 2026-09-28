defmodule Dockd.Catalog do
  @moduledoc """
  Catalog synchronization and Nintendo release data.

  A release synchronized from IGDB is an eShop release, so it is always marked
  as digitally available. Physical availability remains false unless it was
  already known locally; IGDB does not provide a reliable physical inventory
  signal for the catalog.
  """
  import Ecto.Query
  require Logger
  alias Dockd.Catalog.{Game, GameLink, IgdbFamily, Merge, Release}
  alias Dockd.Library.{Ownership, ReleaseVeto}
  alias Dockd.Purchasing.{PriceObservation, Purchase}
  alias Dockd.Repo

  def list_games do
    Repo.all(from game in Game, order_by: [asc: game.title], preload: [:releases])
  end

  def get_game!(id), do: Repo.get!(Game, id) |> Repo.preload(:releases)

  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def update_game(%Game{} = game, attrs) do
    game |> Game.changeset(attrs) |> Repo.update()
  end

  def list_releases(game_id),
    do:
      Repo.all(
        from release in Release,
          where: release.game_id == ^game_id,
          order_by: [asc: release.platform]
      )

  def get_release!(game_id, id), do: Repo.get_by!(Release, id: id, game_id: game_id)

  def create_release(game_id, attrs) do
    game = Repo.get!(Game, game_id)

    %Release{game: game, game_id: game.id}
    |> Release.changeset(attrs)
    |> Repo.insert()
  end

  def update_release(%Release{} = release, attrs) do
    release |> Release.changeset(attrs) |> Repo.update()
  end

  @doc "Deletes a release when no user data refers to it."
  def delete_release(%Release{} = release) do
    blockers =
      [
        {:ownership, Ownership},
        {:purchase, Purchase},
        {:price_observation, PriceObservation},
        {:veto, ReleaseVeto}
      ]
      |> Enum.filter(fn {_name, schema} ->
        Repo.exists?(from record in schema, where: record.release_id == ^release.id)
      end)
      |> Enum.map(&elem(&1, 0))

    if blockers == [], do: Repo.delete(release), else: {:error, {:in_use, blockers}}
  end

  @doc """
  Brings every game with an IGDB id up to date: first its family (`resolve_families/1`),
  then its metadata and Nintendo release dates.
  """
  def sync_igdb do
    if Dockd.IGDB.configured?() do
      family = resolve_families()
      games = Repo.all(from game in Game, where: not is_nil(game.igdb_id), preload: [:releases])
      results = Enum.map(games, &sync_game/1)

      {:ok,
       %{synced: Enum.count(results, &match?({:ok, _}, &1)), results: results, family: family}}
    else
      {:error, :not_configured}
    end
  end

  defp sync_game(game) do
    with {:ok, %{body: [external]}} <- Dockd.IGDB.get_games([game.igdb_id]),
         {:ok, updated} <- Repo.transaction(fn -> apply_external(game, external) end) do
      {:ok, sync_result(updated)}
    else
      {:ok, %{body: []}} -> {:error, {game.id, :not_found}}
      {:error, reason} -> {:error, {game.id, reason}}
    end
  end

  defp apply_external(game, external) do
    attrs = %{
      cover_url: cover_url(external),
      developer: company(external, "developer"),
      publisher: company(external, "publisher"),
      synced_at: DateTime.utc_now()
    }

    {:ok, game} = game |> Game.changeset(attrs) |> Repo.update()

    external_releases(external)
    |> Enum.reduce_while(:ok, fn {platform, date, precision}, :ok ->
      case upsert_release(game, platform, date, precision) do
        {:ok, _release} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> Repo.rollback({:release_sync_failed, reason})
      :ok -> :ok
    end

    suggestion = suggested_availability(external)

    %{
      game: Repo.preload(game, :releases, force: true),
      suggested_availability: suggestion,
      availability_difference: suggestion != game.availability
    }
  end

  defp sync_result(%{game: game} = result),
    do: Map.put(result, :game, %{id: game.id, title: game.title})

  defp upsert_release(game, platform, date, precision) do
    attrs = %{
      release_date: date,
      release_date_precision: precision,
      digital_available: true
    }

    case Repo.get_by(Release,
           game_id: game.id,
           platform: platform,
           edition: Release.standard_edition()
         ) do
      nil ->
        %Release{game_id: game.id}
        |> Release.changeset(Map.merge(%{platform: platform, edition: "Edição padrão"}, attrs))
        |> Repo.insert()

      release ->
        release
        |> Release.changeset(attrs)
        |> Repo.update()
    end
  end

  def suggested_availability(%{"platforms" => platforms}) do
    ids = platforms |> Enum.map(& &1["id"]) |> Enum.uniq()
    nintendo_ids = [Dockd.IGDB.switch_platform_id(), Dockd.IGDB.switch_2_platform_id()]

    cond do
      ids == [Dockd.IGDB.switch_2_platform_id()] ->
        :switch2_exclusive

      ids != [] and Enum.sort(ids) == Enum.sort(nintendo_ids) ->
        :nintendo_exclusive

      ids == [Dockd.IGDB.switch_platform_id()] ->
        :nintendo_exclusive

      Enum.any?(ids, &(&1 in nintendo_ids)) and Enum.any?(ids, &(&1 not in nintendo_ids)) ->
        :multiplatform

      true ->
        nil
    end
  end

  def suggested_availability(_), do: nil

  def release_attributes(external) do
    Enum.map(external_releases(external), fn {platform, date, precision} ->
      %{
        platform: platform,
        edition: "Edição padrão",
        release_date: date,
        release_date_precision: precision,
        digital_available: true
      }
    end)
  end

  defp external_releases(external) do
    platform_ids =
      (external["platforms"] || [])
      |> Enum.map(& &1["id"])
      |> Kernel.++(Enum.map(external["release_dates"] || [], & &1["platform"]))
      |> Enum.filter(
        &(&1 in [Dockd.IGDB.switch_platform_id(), Dockd.IGDB.switch_2_platform_id()])
      )
      |> Enum.uniq()
      |> Enum.sort()

    dates = external["release_dates"] || []

    Enum.map(platform_ids, fn platform_id ->
      release_date =
        dates
        |> Enum.filter(&(&1["platform"] == platform_id))
        |> select_release_date()

      {platform(platform_id), release_date.date, release_date.precision}
    end)
  end

  defp select_release_date([]), do: %{date: nil, precision: :tbd}

  defp select_release_date(dates) do
    dates
    |> Enum.map(fn date ->
      {normalized_date, precision} = normalize_release_date(date)

      %{
        date: normalized_date,
        precision: precision,
        region: date["region"],
        raw_date: date["date"]
      }
    end)
    |> Enum.min_by(fn date ->
      {region_priority(date.region), if(is_nil(date.date), do: 1, else: 0),
       date.date || ~D[9999-12-31], date.raw_date || 9_223_372_036_854_775_807}
    end)
  end

  defp normalize_release_date(%{"date" => date} = release) when is_integer(date) do
    precision = release_precision(release)

    case precision do
      :tbd -> {nil, :tbd}
      _ -> {truncate_date(DateTime.from_unix!(date) |> DateTime.to_date(), precision), precision}
    end
  end

  defp normalize_release_date(_), do: {nil, :tbd}

  defp release_precision(%{"category" => category}) when not is_nil(category),
    do: precision_from_format(category)

  defp release_precision(%{"date_format" => format}), do: precision_from_format(format)
  defp release_precision(_), do: :day

  defp precision_from_format(value) when value in [0, "0", "day", "YYYYMMMMDD"], do: :day
  defp precision_from_format(value) when value in [1, "1", "month", "YYYYMMMM"], do: :month
  defp precision_from_format(value) when value in [2, "2", "year", "YYYY"], do: :year

  defp precision_from_format(value) when value in [3, 4, 5, 6, "3", "4", "5", "6", "quarter"],
    do: :quarter

  defp precision_from_format(value) when value in [7, "7", "tbd", "TBD"], do: :tbd
  defp precision_from_format(_), do: :day

  defp truncate_date(date, :day), do: date
  defp truncate_date(%Date{year: year}, :year), do: Date.new!(year, 1, 1)
  defp truncate_date(%Date{year: year, month: month}, :month), do: Date.new!(year, month, 1)

  defp truncate_date(%Date{year: year, month: month}, :quarter) do
    quarter_month = div(month - 1, 3) * 3 + 1
    Date.new!(year, quarter_month, 1)
  end

  defp truncate_date(date, :tbd), do: date

  defp region_priority(8), do: 0
  defp region_priority(10), do: 1
  defp region_priority(1), do: 2
  defp region_priority(_), do: 3

  defp platform(130), do: :switch
  defp platform(508), do: :switch_2

  defp cover_url(%{"cover" => %{"image_id" => id}}) when is_binary(id),
    do: "https://images.igdb.com/igdb/image/upload/t_cover_big/#{id}.jpg"

  defp cover_url(_), do: nil

  defp company(%{"involved_companies" => companies}, role),
    do:
      companies
      |> Enum.find_value(fn c ->
        if c[role] and get_in(c, ["company", "name"]), do: get_in(c, ["company", "name"])
      end)

  defp company(_, _), do: nil

  @doc """
  Finds a local game by its IGDB identifier, or by another entry that is the same game
  (an edition, the Switch 2 Edition, a merged duplicate).
  """
  def get_game_by_igdb_id(igdb_id) when is_integer(igdb_id),
    do: igdb_id |> List.wrap() |> local_games() |> Map.get(igdb_id)

  # IGDB id => local game, by the game's own id or an accepted link.
  defp local_games([]), do: %{}

  defp local_games(ids) do
    own = Repo.all(from g in Game, where: g.igdb_id in ^ids, preload: :releases)

    linked =
      Repo.all(
        from g in Game,
          join: l in GameLink,
          on: l.game_id == g.id,
          where: l.igdb_id in ^ids and l.match in ^GameLink.accepted(),
          preload: :releases,
          select: {l.igdb_id, g}
      )

    Map.merge(Map.new(linked), Map.new(own, &{&1.igdb_id, &1}))
  end

  @doc """
  Searches IGDB and returns lightweight results, each tagged with the local game when
  the work is already in the catalog. Returns `{:error, :not_configured}` without credentials.
  """
  def search_igdb(query) when is_binary(query) do
    with {:ok, %{body: externals}} <- Dockd.IGDB.search(query),
         do:
           {:ok,
            externals
            |> group_family()
            |> igdb_results()
            |> Enum.sort_by(&{-(&1.year || 0), &1.title})}
  end

  @doc """
  Searches IGDB, or the local catalog by title when IGDB is not available. Returns
  `{:igdb | :local, results}` in the shape of `search_igdb/1`.
  """
  def search(query) when is_binary(query) do
    case search_igdb(query) do
      {:ok, results} ->
        {:igdb, results}

      {:error, _} ->
        needle = String.downcase(query)

        {:local,
         list_games()
         |> Enum.filter(&String.contains?(String.downcase(&1.title), needle))
         |> Enum.map(&local_result/1)}
    end
  end

  @showcase_ttl :timer.hours(1)

  @doc """
  A showcase list, in the shape of `search_igdb/1`: `:upcoming`, `:recent` or `:popular`
  (see `Dockd.IGDB.showcase/2`). IGDB answers are kept for an hour; the local catalog
  stands in when IGDB is not available.
  """
  def showcase(list) when list in [:upcoming, :recent, :popular] do
    today = Date.utc_today()

    case cached_showcase(list) do
      {:ok, externals} -> externals |> igdb_results() |> nintendo_dates(list, today)
      {:error, _} -> local_showcase(list, today)
    end
  end

  # IGDB dates a work by its first release on any platform; the Switch one can differ.
  # Upcoming works known only by year sort after the dated ones.
  defp nintendo_dates(results, :upcoming, today) do
    {dated, by_year} =
      Enum.split_with(results, &(&1.first_date && Date.compare(&1.first_date, today) == :gt))

    Enum.sort_by(dated, & &1.first_date, Date) ++ by_year
  end

  defp nintendo_dates(results, _released, today),
    do: Enum.filter(results, &(&1.first_date && Date.compare(&1.first_date, today) != :gt))

  defp cached_showcase(list) do
    key = {__MODULE__, :showcase, list}
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(key, nil) do
      {expires, externals} when expires > now ->
        {:ok, externals}

      _ ->
        with {:ok, %{body: externals}} <- Dockd.IGDB.showcase(list) do
          externals = group_family(externals)
          :persistent_term.put(key, {now + @showcase_ttl, externals})
          {:ok, externals}
        end
    end
  end

  defp local_showcase(list, today) do
    results = Enum.map(list_games(), &local_result/1)

    case list do
      :upcoming ->
        results
        |> Enum.filter(&(&1.first_date && Date.compare(&1.first_date, today) == :gt))
        |> Enum.sort_by(& &1.first_date, Date)

      :recent ->
        released_since(results, today, 90)

      :popular ->
        released_since(results, today, 365)
    end
  end

  defp released_since(results, today, days) do
    since = Date.add(today, -days)

    results
    |> Enum.filter(&(&1.first_date && Date.compare(&1.first_date, since) == :gt))
    |> Enum.reject(&(Date.compare(&1.first_date, today) == :gt))
    |> Enum.sort_by(& &1.first_date, {:desc, Date})
  end

  defp local_result(%Game{} = game) do
    releases = game.releases || []
    dates = releases |> Enum.map(& &1.release_date) |> Enum.reject(&is_nil/1)
    first = if dates == [], do: nil, else: Enum.min(dates, Date)

    %{
      igdb_id: game.igdb_id,
      title: game.title,
      cover_url: game.cover_url,
      platforms: releases |> Enum.map(& &1.platform) |> Enum.uniq() |> Enum.sort(),
      first_date: first,
      year: first && first.year,
      game: game
    }
  end

  # One card per game: an edition or Switch 2 Edition gives way to its parent, which it
  # joins when both came in the answer and replaces when the parent did not. The Switch
  # 2 Edition adds its platform to the parent's card.
  defp group_family(externals) do
    ids = MapSet.new(externals, & &1["id"])

    children =
      for external <- externals,
          {kind, parent} <- [IgdbFamily.relation(external)],
          IgdbFamily.automatic?(kind),
          do: {external["id"], {kind, parent}}

    children = Map.new(children)

    missing =
      children
      |> Map.values()
      |> Enum.map(&elem(&1, 1))
      |> Enum.reject(&(&1 in ids))
      |> Enum.uniq()

    parents =
      missing
      |> fetch_externals()
      |> Enum.filter(&IgdbFamily.nintendo?/1)
      |> Map.new(&{&1["id"], &1})

    grouped =
      externals
      |> Enum.flat_map(fn external ->
        case Map.fetch(children, external["id"]) do
          {:ok, {_kind, parent}} ->
            cond do
              parent in ids -> []
              Map.has_key?(parents, parent) -> [parents[parent]]
              true -> [external]
            end

          :error ->
            [external]
        end
      end)
      |> Enum.uniq_by(& &1["id"])

    switch_2 =
      for external <- externals,
          {:switch_2_edition, parent} <- [Map.get(children, external["id"])],
          do: {parent, external}

    Enum.map(grouped, fn external ->
      switch_2
      |> Enum.filter(&(elem(&1, 0) == external["id"]))
      |> Enum.reduce(external, fn {_parent, edition}, parent ->
        absorb_platforms(parent, edition)
      end)
    end)
  end

  defp absorb_platforms(parent, child) do
    parent
    |> Map.update("platforms", child["platforms"] || [], &(&1 ++ (child["platforms"] || [])))
    |> Map.update(
      "release_dates",
      child["release_dates"] || [],
      &(&1 ++ (child["release_dates"] || []))
    )
  end

  defp fetch_externals([]), do: []

  defp fetch_externals(ids) do
    ids
    |> Enum.chunk_every(500)
    |> Enum.flat_map(fn chunk ->
      case Dockd.IGDB.get_games(chunk) do
        {:ok, %{body: externals}} when is_list(externals) -> externals
        _ -> []
      end
    end)
  end

  defp igdb_results(externals) do
    ids = Enum.map(externals, & &1["id"])
    local = local_games(ids)

    externals
    |> Enum.map(fn external ->
      releases = release_attributes(external)
      dates = releases |> Enum.map(& &1.release_date) |> Enum.reject(&is_nil/1)
      first = if dates == [], do: nil, else: Enum.min(dates, Date)

      %{
        igdb_id: external["id"],
        title: external["name"],
        cover_url: cover_url(external),
        platforms: releases |> Enum.map(& &1.platform) |> Enum.uniq() |> Enum.sort(),
        first_date: first,
        year: first && first.year,
        game: Map.get(local, external["id"])
      }
    end)
    |> Enum.reject(&(&1.platforms == []))
  end

  @doc """
  Imports an IGDB work into the catalog with its Nintendo releases, or returns the
  existing one. An edition or Switch 2 Edition imports (or finds) its parent game
  instead and joins it; a remaster, expanded game or port of a game already in the
  catalog comes in as a game of its own and waits for a person to say whether it is
  the same one (`list_review_links/0`).
  """
  def import_igdb(igdb_id) when is_integer(igdb_id), do: import_igdb(igdb_id, 2)

  defp import_igdb(igdb_id, depth) do
    case get_game_by_igdb_id(igdb_id) do
      %Game{} = game ->
        {:ok, game}

      nil ->
        with true <- Dockd.IGDB.configured?() || {:error, :not_configured},
             {:ok, external} <- fetch_external(igdb_id) do
          import_external(external, depth)
        end
    end
  end

  defp fetch_external(igdb_id) do
    case Dockd.IGDB.get_games([igdb_id]) do
      {:ok, %{body: [external]}} -> {:ok, external}
      {:ok, %{body: _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # The depth stops an edition of an edition from walking IGDB for good.
  defp import_external(external, depth) do
    with {kind, parent_id} <- IgdbFamily.relation(external),
         true <- depth > 0 and IgdbFamily.automatic?(kind),
         {:ok, parent} <- nintendo_parent(parent_id, depth) do
      apply_family({:link, parent, external["id"], kind, :auto})
      if kind == :switch_2_edition, do: apply_family({:switch_2_release, parent, external})
      {:ok, get_game!(parent.id)}
    else
      _ -> import_own(external)
    end
  end

  # The local game of an IGDB entry sold on a Nintendo platform, imported when missing.
  defp nintendo_parent(igdb_id, depth) do
    case get_game_by_igdb_id(igdb_id) do
      %Game{} = game ->
        {:ok, game}

      nil ->
        with {:ok, external} <- fetch_external(igdb_id),
             true <- IgdbFamily.nintendo?(external) || :not_nintendo,
             do: import_external(external, depth - 1)
    end
  end

  defp import_own(external) do
    with {:ok, game} <- create_game(import_attrs(external)) do
      Enum.each(release_attributes(external), &create_release(game.id, &1))
      game = get_game!(game.id)

      # A doubtful child of a game already here, then the entries that are this game.
      Enum.each(own_actions([{game, external}], MapSet.new()), &apply_family/1)
      Enum.each(children_actions([game]), &apply_family/1)
      {:ok, get_game!(game.id)}
    end
  end

  defp import_attrs(external) do
    %{
      title: external["name"],
      igdb_id: external["id"],
      availability: suggested_availability(external) || :multiplatform,
      cover_url: cover_url(external),
      developer: company(external, "developer"),
      publisher: company(external, "publisher"),
      synced_at: DateTime.utc_now()
    }
  end

  # ---------------------------------------------------------------------------
  # Family: the other IGDB entries that are the same game

  @doc """
  Finds, for every game with an IGDB id, the entries that are the same game, and joins
  them (`Dockd.Catalog.IgdbFamily`): a game imported by its edition's entry moves to
  the parent's id; a duplicate imported as an edition or Switch 2 Edition merges into
  its parent; the Switch 2 Edition becomes the parent's Switch 2 release. A remaster,
  expanded game or port whose parent is also here waits for review.

  With `dry_run: true` nothing changes. Returns the steps, as
  `%{step:, game:, igdb_id:, kind:}`.
  """
  def resolve_families(opts \\ []) do
    if Dockd.IGDB.configured?() do
      games = igdb_games()
      externals = games |> Enum.map(& &1.igdb_id) |> fetch_externals() |> Map.new(&{&1["id"], &1})
      pairs = for game <- games, external = externals[game.igdb_id], do: {game, external}
      own = own_actions(pairs, nintendo_parents(pairs))

      if Keyword.get(opts, :dry_run, false) do
        Enum.map(own ++ children_actions(games), &describe/1)
      else
        Enum.each(own, &apply_family/1)
        children = children_actions(igdb_games())
        Enum.each(children, &apply_family/1)
        Enum.map(own ++ children, &describe/1)
      end
    else
      {:error, :not_configured}
    end
  end

  defp igdb_games,
    do: Repo.all(from g in Game, where: not is_nil(g.igdb_id), preload: :releases)

  # The parents, not in the catalog, that are sold on a Nintendo platform.
  defp nintendo_parents(pairs) do
    ids =
      for {_game, external} <- pairs,
          {kind, parent} <- [IgdbFamily.relation(external)],
          IgdbFamily.automatic?(kind),
          uniq: true,
          do: parent

    local = local_games(ids)

    ids
    |> Enum.reject(&Map.has_key?(local, &1))
    |> fetch_externals()
    |> Enum.filter(&IgdbFamily.nintendo?/1)
    |> MapSet.new(& &1["id"])
  end

  # What a game's own entry says: it is an edition of another game.
  defp own_actions(pairs, nintendo) do
    parents =
      pairs
      |> Enum.flat_map(fn {_game, external} ->
        case IgdbFamily.relation(external) do
          {_kind, parent} -> [parent]
          :own -> []
        end
      end)
      |> local_games()

    linked = linked_ids(Enum.map(pairs, &elem(&1, 0).igdb_id))

    Enum.flat_map(pairs, fn {game, external} ->
      own_action(game, IgdbFamily.relation(external), parents, nintendo, linked)
    end)
  end

  defp own_action(_game, :own, _parents, _nintendo, _linked), do: []

  defp own_action(game, {kind, parent_id}, parents, nintendo, linked) do
    parent = parents[parent_id]
    other? = parent != nil and parent.id != game.id
    automatic? = IgdbFamily.automatic?(kind)

    cond do
      automatic? and other? -> [{:merge, parent, game, kind}]
      automatic? and parent_id in nintendo -> [{:repoint, game, parent_id, kind}]
      other? and game.igdb_id not in linked -> [{:link, parent, game.igdb_id, kind, :review}]
      true -> []
    end
  end

  # What IGDB lists as editions and children of the games.
  defp children_actions(games) do
    parents = Map.new(games, &{&1.igdb_id, &1})
    children = children(Map.keys(parents))
    ids = Enum.map(children, & &1["id"])
    own = Repo.all(from g in Game, where: g.igdb_id in ^ids) |> Map.new(&{&1.igdb_id, &1})
    linked = linked_ids(ids)

    Enum.flat_map(children, fn child ->
      with {kind, parent_id} <- IgdbFamily.relation(child),
           %Game{} = parent <- parents[parent_id] do
        child_actions(parent, child, kind, own[child["id"]], child["id"] in linked)
      else
        _ -> []
      end
    end)
  end

  defp child_actions(parent, child, kind, own, linked?) do
    duplicate? = own != nil and own.id != parent.id

    cond do
      not IgdbFamily.automatic?(kind) ->
        if duplicate? and not linked?, do: [{:link, parent, child["id"], kind, :review}], else: []

      duplicate? ->
        [{:merge, parent, own, kind} | switch_2_actions(parent, child, kind)]

      linked? ->
        switch_2_actions(parent, child, kind)

      true ->
        [{:link, parent, child["id"], kind, :auto} | switch_2_actions(parent, child, kind)]
    end
  end

  defp switch_2_actions(parent, child, :switch_2_edition) do
    if switch_2_changed?(parent, child), do: [{:switch_2_release, parent, child}], else: []
  end

  defp switch_2_actions(_parent, _child, _kind), do: []

  # Whether the parent lacks the Switch 2 release the edition describes, or dates it
  # differently.
  defp switch_2_changed?(%Game{releases: releases}, child) when is_list(releases) do
    current =
      Enum.find(releases, &(&1.platform == :switch_2 and Release.standard?(&1)))

    case Enum.find(external_releases(child), &(elem(&1, 0) == :switch_2)) do
      nil ->
        false

      {_, date, precision} ->
        current == nil or
          {current.release_date, current.release_date_precision} != {date, precision}
    end
  end

  defp switch_2_changed?(_parent, _child), do: true

  defp children([]), do: []

  defp children(ids) do
    ids
    |> Enum.chunk_every(100)
    |> Enum.flat_map(fn chunk ->
      case Dockd.IGDB.children(chunk) do
        {:ok, children} ->
          children

        {:error, reason} ->
          Logger.warning("IGDB: edições e versões não lidas: #{inspect(reason)}")
          []
      end
    end)
  end

  defp linked_ids(ids),
    do: Repo.all(from l in GameLink, where: l.igdb_id in ^ids, select: l.igdb_id) |> MapSet.new()

  defp apply_family({:link, game, igdb_id, kind, match}) do
    %GameLink{}
    |> GameLink.changeset(%{igdb_id: igdb_id, game_id: game.id, kind: kind, match: match})
    |> Repo.insert(on_conflict: :nothing, conflict_target: :igdb_id)
  end

  defp apply_family({:switch_2_release, game, child}) do
    case Enum.find(external_releases(child), &(elem(&1, 0) == :switch_2)) do
      {platform, date, precision} -> upsert_release(game, platform, date, precision)
      nil -> :ok
    end
  end

  defp apply_family({:merge, winner, loser, kind}),
    do: merge_games(winner, loser, kind: kind, match: :auto)

  defp apply_family({:repoint, game, parent_id, kind}) do
    Repo.transaction(fn ->
      game |> Game.changeset(%{igdb_id: parent_id}) |> Repo.update!()
      apply_family({:link, game, game.igdb_id, kind, :auto})
    end)
  end

  defp describe({step, game, igdb_id, kind, match}) when step == :link,
    do: %{step: :link, game: brief(game), igdb_id: igdb_id, kind: kind, match: match}

  defp describe({:switch_2_release, game, child}),
    do: %{
      step: :switch_2_release,
      game: brief(game),
      igdb_id: child["id"],
      kind: :switch_2_edition
    }

  defp describe({:merge, winner, loser, kind}),
    do: %{
      step: :merge,
      game: brief(winner),
      igdb_id: loser.igdb_id,
      kind: kind,
      merged: brief(loser)
    }

  defp describe({:repoint, game, parent_id, kind}),
    do: %{step: :repoint, game: brief(game), igdb_id: parent_id, kind: kind, from: game.igdb_id}

  defp brief(game), do: %{id: game.id, title: game.title}

  @doc """
  Merges `loser` into `winner`, for good: every release, with its ownerships,
  purchases, price observations, vetoes, events and store listing, moves to the winner
  (`Dockd.Catalog.Merge`); the accounts' entries become one; the loser's IGDB id becomes
  a link of the winner (`kind`, default `:merged`; `match`, default `:confirmed`).
  """
  def merge_games(winner, loser, opts \\ [])

  def merge_games(%Game{id: id}, %Game{id: id}, _opts), do: {:error, :same_game}

  def merge_games(%Game{} = winner, %Game{} = loser, opts) do
    with {:ok, game, _undo} <- merge(winner, loser, opts), do: {:ok, game}
  end

  defp merge(winner, loser, opts) do
    link = %{
      kind: Keyword.get(opts, :kind, :merged),
      match: Keyword.get(opts, :match, :confirmed)
    }

    Ecto.Multi.new()
    |> Ecto.Multi.run(:releases, fn repo, _ -> Merge.releases(repo, winner.id, loser.id) end)
    |> Ecto.Multi.run(:entries, fn repo, _ -> Merge.entries(repo, winner.id, loser.id) end)
    |> Ecto.Multi.run(:games, fn repo, _ -> Merge.game(repo, winner.id, loser, link) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{releases: releases, entries: entries, games: games}} ->
        {:ok, get_game!(winner.id), %Merge.Undo{ops: releases ++ entries ++ games}}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Puts two merged games back as they were, from what `confirm_game_link/1` returned:
  the link that asked is in review again. Only while the screen that merged them is
  open, and before anything else touched them.
  """
  def undo_merge(%Merge.Undo{ops: ops}) do
    case Repo.transaction(fn -> Merge.undo(Repo, ops) end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [Ecto.ConstraintError, Postgrex.Error] -> {:error, error}
  end

  @doc "Links waiting for a person: `%{link:, game:, candidate:}`, the candidate being the game that may be `game`."
  def list_review_links do
    Repo.all(
      from l in GameLink,
        join: g in assoc(l, :game),
        join: c in Game,
        on: c.igdb_id == l.igdb_id,
        where: l.match == :review,
        order_by: [asc: g.title],
        preload: [game: {g, :releases}],
        select: {l, c}
    )
    |> Enum.map(fn {link, candidate} ->
      %{link: link, game: link.game, candidate: Repo.preload(candidate, :releases)}
    end)
  end

  @doc "How many links wait for review."
  def review_link_count,
    do: Repo.aggregate(from(l in GameLink, where: l.match == :review), :count)

  @doc "A game link."
  def get_game_link!(id), do: Repo.get!(GameLink, id)

  @doc """
  It is the same game: the candidate merges into the linked game. Returns the game and
  what `undo_merge/1` needs to put them apart again.
  """
  def confirm_game_link(%GameLink{match: :review} = link) do
    game = Repo.get!(Game, link.game_id)

    case Repo.get_by(Game, igdb_id: link.igdb_id) do
      nil ->
        with {:ok, _} <- link |> GameLink.changeset(%{match: :confirmed}) |> Repo.update() do
          ops = [{:set, GameLink, [link.id], [match: :review, updated_at: link.updated_at]}]
          {:ok, get_game!(game.id), %Merge.Undo{ops: ops}}
        end

      candidate ->
        merge(game, candidate, kind: link.kind, match: :confirmed)
    end
  end

  def confirm_game_link(%GameLink{}), do: {:error, :not_in_review}

  @doc "It is another game: the link stays rejected and is not asked again."
  def reject_game_link(%GameLink{match: :review} = link),
    do: link |> GameLink.changeset(%{match: :rejected}) |> Repo.update()

  def reject_game_link(%GameLink{}), do: {:error, :not_in_review}

  @doc "Desfazer after It is another game: the link waits for review again."
  def reopen_game_link(%GameLink{match: :rejected} = link),
    do: link |> GameLink.changeset(%{match: :review}) |> Repo.update()

  def reopen_game_link(%GameLink{}), do: {:error, :not_rejected}

  def match_igdb(opts \\ []) do
    if Dockd.IGDB.configured?() do
      dry_run = Keyword.get(opts, :dry_run, false)
      games = Repo.all(from game in Game, where: is_nil(game.igdb_id))
      classified = Enum.map(games, &classify_match/1)
      matches = Enum.filter(classified, &(&1.status == :matched))

      unless dry_run, do: apply_matches(matches)

      %{
        matched: Enum.map(matches, &match_result/1),
        ambiguous:
          classified |> Enum.filter(&(&1.status == :ambiguous)) |> Enum.map(&match_result/1),
        not_found:
          classified |> Enum.filter(&(&1.status == :not_found)) |> Enum.map(&match_result/1)
      }
    else
      {:error, :not_configured}
    end
  end

  defp apply_matches(matches) do
    Enum.each(matches, fn item ->
      Repo.update!(Game.changeset(item.game, %{igdb_id: item.candidate["id"]}))
    end)
  end

  defp classify_match(game) do
    candidates = search_candidates(game.title)
    switch = candidates |> Enum.filter(&switch_candidate?/1) |> Enum.uniq_by(& &1["id"])

    exact = Enum.filter(switch, &exact_title?(game.title, &1))
    variants = Enum.filter(switch, &obvious_variant?(game.title, &1))

    {status, candidate} = select_candidate(exact, variants)
    %{game: game, status: if(candidate == [], do: :not_found, else: status), candidate: candidate}
  end

  defp search_candidates(title) do
    case Dockd.IGDB.search(title) do
      {:ok, %{body: body}} -> body
      _ -> []
    end
  end

  defp switch_candidate?(candidate),
    do: Enum.any?(candidate["platforms"] || [], &(&1["id"] in [130, 508]))

  defp exact_title?(title, candidate),
    do: Enum.any?(candidate_titles(candidate), &(normalize_title(&1) == normalize_title(title)))

  defp obvious_variant?(title, candidate) do
    normalized_title = normalize_title(title)

    Enum.any?(candidate_titles(candidate), fn name ->
      normalized_name = normalize_title(name)

      normalized_title != normalized_name and
        String.starts_with?(normalized_name, normalized_title <> " ")
    end)
  end

  defp candidate_titles(candidate) do
    [candidate["name"] | Enum.map(candidate["alternative_names"] || [], & &1["name"])]
    |> Enum.filter(&is_binary/1)
  end

  defp normalize_title(title) do
    title
    |> String.replace("&", " and ")
    |> String.normalize(:nfd)
    |> String.replace(~r/[\p{Mn}]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/\b(?:iii|3)\b/u, "3")
    |> String.replace(~r/\b(?:ii|2)\b/u, "2")
    |> String.replace(~r/\b(?:iv|4)\b/u, "4")
  end

  defp select_candidate([one], _switch), do: {:matched, one}
  defp select_candidate(exact, _switch) when exact != [], do: {:ambiguous, exact}
  defp select_candidate([], [one]), do: {:matched, one}
  defp select_candidate([], switch), do: {:ambiguous, switch}

  defp match_result(%{game: game, candidate: candidate}),
    do: %{game_id: game.id, title: game.title, candidate: candidate}
end
