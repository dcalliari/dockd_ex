defmodule Dockd.Social do
  @moduledoc """
  Public profiles and following (`maquetes/perfil-social.html`, decided on 28/09/2026).

  Following goes one way; when two accounts follow each other they are friends. A profile
  is public on the web by default, or only for friends. What a profile shows is the
  library read model (`Dockd.Library.Shelf`) and the status changes of the activity log;
  prices, purchases and the Comprar queue never leave the account.
  """
  import Ecto.Query

  alias Dockd.Accounts.User
  alias Dockd.Activity.Event
  alias Dockd.Catalog.Game
  alias Dockd.Library.{Entry, Shelf}
  alias Dockd.Repo
  alias Dockd.Social.{Follow, ProfileFavorite}

  @playing [:playing, :paused]
  @wanting ~w(want planned preordered)
  @search_limit 30

  @doc "The account whose profile lives at `/u/:username`. Raises when there is none."
  def get_profile!(username) when is_binary(username),
    do: Repo.get_by!(User, username: username)

  @doc """
  Accounts whose username or name match `query`, for the Usuários tab of the search bar
  (`Dockd.Catalog.search/1` is the Jogos tab). Each result carries what `person_row/1`
  shows, the same fields as the followers and followed lists, and a profile in `:friends`
  visibility that `viewer` cannot see stays out, exactly like `visible?/2` on `/u/:username`.
  """
  def search_users(query, viewer) when is_binary(query) do
    case String.trim(query) do
      "" ->
        []

      term ->
        pattern = "%" <> escape_like(term) <> "%"

        users =
          Repo.all(
            from u in User,
              where: ilike(u.username, ^pattern) or ilike(u.name, ^pattern),
              order_by: [asc: u.username],
              limit: @search_limit
          )

        ids = Enum.map(users, & &1.id)
        relations = relations(viewer, ids)
        playing = playing_map(ids)
        finished = finished_map(ids)

        users
        |> Enum.map(fn user ->
          %{
            user: user,
            playing: playing[user.id],
            finished: Map.get(finished, user.id, 0),
            relation: relations[user.id]
          }
        end)
        |> Enum.filter(&visible?(&1.user, &1.relation))
    end
  end

  defp escape_like(term), do: String.replace(term, ~r/[\\%_]/, fn c -> "\\" <> c end)

  @doc "`user` follows `target`. Following twice keeps one follow."
  def follow(%User{id: id}, %User{id: id}), do: {:error, :self}

  def follow(%User{} = user, %User{} = target) do
    %Follow{}
    |> Follow.changeset(%{follower_id: user.id, followed_id: target.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:follower_id, :followed_id])
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "`user` stops following `target`."
  def unfollow(%User{} = user, %User{} = target) do
    Repo.delete_all(
      from f in Follow, where: f.follower_id == ^user.id and f.followed_id == ^target.id
    )

    :ok
  end

  @doc """
  How `viewer` relates to `owner`: `:visitor` without an account, `:self`, `:friends`
  when each follows the other, `:following`, `:followed_by` or `:none`.
  """
  def relation(nil, %User{}), do: :visitor
  def relation(%User{id: id}, %User{id: id}), do: :self

  def relation(%User{} = viewer, %User{} = owner),
    do: viewer |> relations([owner.id]) |> Map.fetch!(owner.id)

  defp relations(nil, ids), do: Map.new(ids, &{&1, :visitor})

  defp relations(%User{id: viewer_id}, ids) do
    following =
      Repo.all(
        from f in Follow,
          where: f.follower_id == ^viewer_id and f.followed_id in ^ids,
          select: f.followed_id
      )

    followers =
      Repo.all(
        from f in Follow,
          where: f.followed_id == ^viewer_id and f.follower_id in ^ids,
          select: f.follower_id
      )

    Map.new(ids, fn id ->
      {id, relation_of(id == viewer_id, id in following, id in followers)}
    end)
  end

  defp relation_of(true, _, _), do: :self
  defp relation_of(_, true, true), do: :friends
  defp relation_of(_, true, false), do: :following
  defp relation_of(_, false, true), do: :followed_by
  defp relation_of(_, false, false), do: :none

  @doc "Whether a viewer with this relation sees the library and lists of `owner`."
  def visible?(%User{profile_visibility: :public}, _relation), do: true
  def visible?(%User{}, relation), do: relation in [:self, :friends]

  @doc "Who sees the profile: `:public` or `:friends`."
  def set_visibility(%User{} = user, visibility),
    do: user |> User.visibility_changeset(visibility) |> Repo.update()

  @doc "How many accounts `user` follows and how many follow it."
  def counts(%User{id: id}) do
    %{
      following: Repo.aggregate(from(f in Follow, where: f.follower_id == ^id), :count),
      followers: Repo.aggregate(from(f in Follow, where: f.followed_id == ^id), :count)
    }
  end

  @doc "The four games a person chose as the signature of their profile."
  def favorites(%User{id: user_id}) do
    Repo.all(
      from f in ProfileFavorite,
        where: f.user_id == ^user_id,
        order_by: f.position,
        preload: [game: :releases]
    )
  end

  @slots 1..4

  @doc """
  The four positions of the profile editor, one entry each: the favorite there or `nil`.
  """
  def favorite_slots(%User{} = user) do
    by_position = Map.new(favorites(user), &{&1.position, &1})
    Enum.map(@slots, &by_position[&1])
  end

  @doc """
  Puts `game`, any game of the catalog, in `position` (1 to 4). The game that was there
  leaves, unless `game` came from another position, which then takes its place.
  """
  def put_favorite(%User{} = user, %Game{id: game_id}, position) when position in @slots do
    update_favorite_slots(user, fn slots ->
      from = Enum.find_value(slots, fn {at, id} -> id == game_id && at end)
      displaced = slots[position]

      slots
      |> Map.delete(from)
      |> Map.put(position, game_id)
      |> then(&if(from && displaced, do: Map.put(&1, from, displaced), else: &1))
    end)
  end

  @doc "Empties `position`; the other favorites keep theirs."
  def clear_favorite(%User{} = user, position) when position in @slots,
    do: update_favorite_slots(user, &Map.delete(&1, position))

  defp update_favorite_slots(%User{id: user_id}, update) do
    Repo.transaction(fn ->
      Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE")
      slots = slot_games(%User{id: user_id})
      save_slots(user_id, update.(slots))
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp slot_games(%User{id: user_id}) do
    Repo.all(
      from f in ProfileFavorite, where: f.user_id == ^user_id, select: {f.position, f.game_id}
    )
    |> Map.new()
  end

  # Rewrites the whole set in one transaction: four rows at most, and a swap would
  # otherwise trip the unique position index halfway.
  defp save_slots(user_id, slots) do
    now = DateTime.utc_now()
    Repo.delete_all(from f in ProfileFavorite, where: f.user_id == ^user_id)

    Repo.insert_all(
      ProfileFavorite,
      for {position, game_id} <- slots do
        %{
          id: Ecto.UUID.generate(),
          user_id: user_id,
          game_id: game_id,
          position: position,
          inserted_at: now
        }
      end
    )
  end

  @doc """
  How many games `user` has in each of the six statuses, for the profile's Estante bar.
  Counts only: no price, purchase, platform or media.
  """
  def profile_stats(%User{} = user) do
    items = Shelf.list(user)
    counts = Enum.frequencies_by(items, & &1.status)

    %{
      games: length(items),
      statuses: Map.new(Shelf.statuses(), &{&1, Map.get(counts, &1, 0)})
    }
  end

  @doc """
  What the diary says about one `year`: how many records it holds and how many games
  were finished in each month (a list of twelve counts, January first).
  """
  def year_summary(diary, year) do
    entries = Enum.filter(diary, &(DateTime.to_date(&1.at).year == year))

    finished =
      entries
      |> Enum.filter(&(&1.status == :zerado))
      |> Enum.frequencies_by(&DateTime.to_date(&1.at).month)

    %{records: length(entries), finished: Enum.map(1..12, &Map.get(finished, &1, 0))}
  end

  @doc """
  The newest `limit` diary entries grouped by month, newest month first, as
  `{first_day_of_month, entries}`.
  """
  def diary_months(diary, limit) do
    diary
    |> Enum.take(limit)
    |> Enum.chunk_by(&month_start(&1.at))
    |> Enum.map(fn [first | _] = entries -> {month_start(first.at), entries} end)
  end

  defp month_start(at), do: at |> DateTime.to_date() |> Date.beginning_of_month()

  @doc """
  The followers or the followed accounts of `owner`, newest follow first, each with the
  game it plays most recently, how many it finished and its relation to `viewer`.
  """
  def people(%User{id: owner_id}, direction, viewer) when direction in [:followers, :following] do
    users =
      case direction do
        :followers ->
          from f in Follow,
            join: u in assoc(f, :follower),
            where: f.followed_id == ^owner_id,
            order_by: [desc: f.inserted_at],
            select: u

        :following ->
          from f in Follow,
            join: u in assoc(f, :followed),
            where: f.follower_id == ^owner_id,
            order_by: [desc: f.inserted_at],
            select: u
      end
      |> Repo.all()

    ids = Enum.map(users, & &1.id)
    playing = playing_map(ids)
    finished = finished_map(ids)
    relations = relations(viewer, ids)

    Enum.map(users, fn user ->
      %{
        user: user,
        playing: playing[user.id],
        finished: Map.get(finished, user.id, 0),
        relation: relations[user.id]
      }
    end)
  end

  @doc """
  What the friends of `user` play now, most recent first, one item per game with the
  names of the friends playing it.
  """
  def friends_playing(%User{} = user, limit \\ 7) do
    friends =
      from f in Follow,
        join: back in Follow,
        on: back.follower_id == f.followed_id and back.followed_id == f.follower_id,
        where: f.follower_id == ^user.id,
        select: f.followed_id

    Repo.all(
      from e in Entry,
        join: u in assoc(e, :user),
        where: e.user_id in subquery(friends) and e.play_state in ^@playing,
        order_by: [desc: e.updated_at, asc: u.name],
        preload: [game: :releases],
        select: {e, u.name}
    )
    |> Enum.reduce({[], %{}}, fn {entry, name}, {order, names} ->
      if Map.has_key?(names, entry.game_id),
        do: {order, Map.update!(names, entry.game_id, &(&1 ++ [name]))},
        else: {[entry.game | order], Map.put(names, entry.game_id, [name])}
    end)
    |> then(fn {order, names} ->
      order |> Enum.reverse() |> Enum.take(limit) |> Enum.map(&%{game: &1, names: names[&1.id]})
    end)
  end

  @doc """
  The Estante of a profile: the items of Jogando, Zerado and Quero, each list with the
  most recent change first. Backlog and Larguei stay out of the profile.
  """
  def shelf(%User{} = owner) do
    items = owner |> Shelf.list() |> Enum.sort_by(&changed_at/1, {:desc, DateTime})

    Map.new([:jogando, :zerado, :quero], fn status ->
      {status, Enum.filter(items, &(&1.status == status))}
    end)
  end

  defp changed_at(%Shelf{entry: %Entry{updated_at: at}}), do: at
  defp changed_at(_item), do: ~U[1970-01-01 00:00:00Z]

  @doc """
  The Diário of a profile (`maquetes/perfil-diario.html`, caminho A): every status change
  of `owner`, newest first, each with the status it marked. Games that left the library
  stay out, and so do purchases, prices, ownership and vetoes.
  """
  def diary(%User{id: owner_id} = owner) do
    shelf = owner |> Shelf.list() |> Map.new(&{&1.game.id, &1})

    owner_id
    |> status_events()
    |> Enum.flat_map(fn event ->
      with {status, _verb} <- change(event),
           %Shelf{} = item <- shelf[event.game_id] do
        [%{id: event.id, item: item, status: status, at: event.occurred_at}]
      else
        _ -> []
      end
    end)
  end

  defp status_events(owner_id) do
    Repo.all(
      from e in Event,
        where:
          e.user_id == ^owner_id and
            e.type in [
              :added,
              :intent_changed,
              :started,
              :resumed,
              :paused,
              :finished,
              :abandoned
            ],
        order_by: [desc: e.occurred_at],
        limit: 500
    )
  end

  defp change(%Event{type: :started}), do: {:jogando, "Começou a jogar"}
  defp change(%Event{type: :resumed}), do: {:jogando, "Voltou a jogar"}
  defp change(%Event{type: :paused}), do: {:jogando, "Pausou"}
  defp change(%Event{type: :finished}), do: {:zerado, "Zerou"}
  defp change(%Event{type: :abandoned}), do: {:larguei, "Largou"}

  # A game that enters the library already in a status logs only :added, with that status.
  defp change(%Event{type: :added, payload: %{"play_state" => state}})
       when state in ["playing", "paused"],
       do: {:jogando, "Começou a jogar"}

  defp change(%Event{type: :added, payload: %{"play_state" => "finished"}}),
    do: {:zerado, "Zerou"}

  defp change(%Event{type: :added, payload: %{"play_state" => "abandoned"}}),
    do: {:larguei, "Largou"}

  defp change(%Event{type: :added, payload: %{"purchase_intent" => intent}})
       when intent in @wanting,
       do: {:quero, "Quer"}

  defp change(%Event{
         type: :intent_changed,
         payload: %{"field" => "purchase_intent", "value" => intent}
       })
       when intent in @wanting,
       do: {:quero, "Quer"}

  # Entering the library without wanting it is entering owned: Backlog needs an ownership.
  # :backlogged stays out: a purchase writes it, and the profile never shows purchases.
  defp change(%Event{type: :added}), do: {:backlog, "Entrou na biblioteca"}
  defp change(_event), do: nil

  # The game each account of `ids` plays most recently, for the PersonRow thumbnail.
  defp playing_map(ids) do
    Repo.all(
      from e in Entry,
        where: e.user_id in ^ids and e.play_state in ^@playing,
        order_by: [desc: e.updated_at],
        preload: :game
    )
    |> Enum.uniq_by(& &1.user_id)
    |> Map.new(&{&1.user_id, &1.game})
  end

  # How many games each account of `ids` finished, for the PersonRow meta.
  defp finished_map(ids) do
    Repo.all(
      from e in Entry,
        where: e.user_id in ^ids and e.play_state == :finished,
        group_by: e.user_id,
        select: {e.user_id, count(e.id)}
    )
    |> Map.new()
  end
end
