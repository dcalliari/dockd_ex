defmodule Dockd.Catalog do
  @moduledoc """
  Catalog synchronization and Nintendo release data.

  A release synchronized from IGDB is an eShop release, so it is always marked
  as digitally available. Physical availability remains false unless it was
  already known locally; IGDB does not provide a reliable physical inventory
  signal for the catalog.
  """
  import Ecto.Query
  alias Dockd.Catalog.{Game, Release}
  alias Dockd.Library.{Ownership, ReleaseVeto}
  alias Dockd.Purchasing.{PriceObservation, Purchase}
  alias Dockd.Repo
  alias Dockd.Wallet.BalanceReservation

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

    reservation? =
      Repo.exists?(
        from reservation in BalanceReservation, where: reservation.game_id == ^release.game_id
      )

    blockers = if reservation?, do: blockers ++ [:reservation], else: blockers

    if blockers == [], do: Repo.delete(release), else: {:error, {:in_use, blockers}}
  end

  def sync_igdb do
    if Dockd.IGDB.configured?() do
      games = Repo.all(from game in Game, where: not is_nil(game.igdb_id), preload: [:releases])
      results = Enum.map(games, &sync_game/1)
      {:ok, %{synced: Enum.count(results, &match?({:ok, _}, &1)), results: results}}
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

    case Repo.one(
           from release in Release,
             where: release.game_id == ^game.id and release.platform == ^platform,
             limit: 1
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

  @doc "Finds a local game by its IGDB identifier."
  def get_game_by_igdb_id(igdb_id) when is_integer(igdb_id),
    do: Repo.one(from g in Game, where: g.igdb_id == ^igdb_id, preload: :releases)

  @doc """
  Searches IGDB and returns lightweight results, each tagged with the local game when
  the work is already in the catalog. Returns `{:error, :not_configured}` without credentials.
  """
  def search_igdb(query) when is_binary(query) do
    with {:ok, %{body: externals}} <- Dockd.IGDB.search(query),
         do: {:ok, externals |> igdb_results() |> Enum.sort_by(&{-(&1.year || 0), &1.title})}
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

  defp igdb_results(externals) do
    ids = Enum.map(externals, & &1["id"])

    local =
      Repo.all(from g in Game, where: g.igdb_id in ^ids, preload: :releases)
      |> Map.new(&{&1.igdb_id, &1})

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

  @doc "Imports an IGDB work into the catalog with its Nintendo releases, or returns the existing one."
  def import_igdb(igdb_id) when is_integer(igdb_id) do
    case get_game_by_igdb_id(igdb_id) do
      %Game{} = game ->
        {:ok, game}

      nil ->
        with true <- Dockd.IGDB.configured?() || {:error, :not_configured},
             {:ok, %{body: [external]}} <- Dockd.IGDB.get_games([igdb_id]),
             {:ok, game} <- create_game(import_attrs(external)) do
          Enum.each(release_attributes(external), &create_release(game.id, &1))
          {:ok, get_game!(game.id)}
        else
          {:ok, %{body: []}} -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
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
