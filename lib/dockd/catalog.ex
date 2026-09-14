defmodule Dockd.Catalog do
  @moduledoc false
  import Ecto.Query
  alias Dockd.Catalog.{Game, Release}
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
    |> Enum.reduce_while(:ok, fn {platform, date}, :ok ->
      case upsert_release(game, platform, date) do
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
      game: Repo.preload(game, :releases),
      suggested_availability: suggestion,
      availability_difference: suggestion != game.availability
    }
  end

  defp sync_result(%{game: game} = result),
    do: Map.put(result, :game, %{id: game.id, title: game.title})

  defp upsert_release(game, platform, date) do
    case Repo.one(
           from release in Release,
             where: release.game_id == ^game.id and release.platform == ^platform,
             limit: 1
         ) do
      nil ->
        %Release{game_id: game.id}
        |> Release.changeset(%{platform: platform, edition: "Edição padrão", release_date: date})
        |> Repo.insert()

      release ->
        release
        |> Release.changeset(%{release_date: date})
        |> Repo.update()
    end
  end

  defp suggested_availability(%{"platforms" => platforms}) do
    ids = Enum.map(platforms, & &1["id"])

    cond do
      ids == [508] -> :switch2_exclusive
      ids == [130] -> :nintendo_exclusive
      130 in ids or 508 in ids -> :multiplatform
      true -> nil
    end
  end

  defp suggested_availability(_), do: nil

  defp external_releases(%{"release_dates" => dates}) do
    dates
    |> Enum.filter(
      &(&1["platform"] in [Dockd.IGDB.switch_platform_id(), Dockd.IGDB.switch_2_platform_id()])
    )
    |> Enum.reduce(%{}, fn item, acc ->
      Map.put(acc, platform(item["platform"]), unix_date(item["date"]))
    end)
    |> Map.to_list()
  end

  defp external_releases(_), do: []
  defp platform(130), do: :switch
  defp platform(508), do: :switch_2
  defp unix_date(nil), do: nil
  defp unix_date(seconds), do: DateTime.from_unix!(seconds) |> DateTime.to_date()

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

  def match_igdb(opts \\ []) do
    if Dockd.IGDB.configured?() do
      dry_run = Keyword.get(opts, :dry_run, false)
      games = Repo.all(Game)
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
    switch = Enum.filter(candidates, &switch_candidate?/1)

    exact =
      Enum.filter(switch, &(String.downcase(&1["name"] || "") == String.downcase(game.title)))

    {status, candidate} = select_candidate(exact, switch)
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

  defp select_candidate(_exact, []), do: {:ambiguous, []}
  defp select_candidate(_exact, [one]), do: {:matched, one}
  defp select_candidate(_exact, switch), do: {:ambiguous, switch}

  defp match_result(%{game: game, candidate: candidate}),
    do: %{game_id: game.id, title: game.title, candidate: candidate}
end
