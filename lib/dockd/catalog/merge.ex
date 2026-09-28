defmodule Dockd.Catalog.Merge do
  @moduledoc """
  The steps of `Dockd.Catalog.merge_games/3`, run inside its transaction.

  A release of the absorbed game changes owner when the winner has no release of the
  same platform and edition. When it has, everything pointing to the absorbed release
  moves to the winner's: purchases, price observations and events as they are; a
  repeated ownership (same account and media) stays one, with the earliest date and
  the purchase kept; a repeated veto stays one; an accepted store listing wins over
  one in review, and keeps its price history.

  Every step returns the operations that put back what it changed, in the order it
  changed them, so `undo/2` can reverse a merge while the screen that asked for it is
  open (Desfazer): `{:set, schema, ids, fields}`, `{:insert, schema, rows}` and
  `{:delete, schema, ids}`.
  """
  import Ecto.Query
  alias Dockd.Activity.Event
  alias Dockd.Catalog.{Game, GameLink, Release}
  alias Dockd.Library.{Entry, Ownership, ReleaseVeto}
  alias Dockd.Pricing.{StoreListing, StorePrice}
  alias Dockd.Purchasing.{PriceObservation, Purchase}

  @priorities [:low, :normal, :high]

  def releases(repo, winner_id, loser_id) do
    now = DateTime.utc_now()

    ops =
      for release <- repo.all(from r in Release, where: r.game_id == ^loser_id) do
        case repo.get_by(Release,
               game_id: winner_id,
               platform: release.platform,
               edition: release.edition
             ) do
          nil ->
            repo.update_all(from(r in Release, where: r.id == ^release.id),
              set: [game_id: winner_id, updated_at: now]
            )

            [{:set, Release, [release.id], [game_id: loser_id, updated_at: release.updated_at]}]

          target ->
            fold(repo, release, target.id)
        end
      end

    {:ok, List.flatten(ops)}
  end

  defp fold(repo, release, into_id) do
    from_id = release.id
    owned = ownerships(repo, from_id, into_id)

    moved =
      for schema <- [Purchase, PriceObservation, Event],
          do: move(repo, from(x in schema, where: x.release_id == ^from_id), release_id: into_id)

    vetoed = from v in ReleaseVeto, where: v.release_id == ^into_id, select: v.user_id

    repeated =
      delete(
        repo,
        from(v in ReleaseVeto, where: v.release_id == ^from_id and v.user_id in subquery(vetoed))
      )

    vetoes =
      move(repo, from(v in ReleaseVeto, where: v.release_id == ^from_id), release_id: into_id)

    listing = listing(repo, from_id, into_id)
    gone = delete(repo, from(r in Release, where: r.id == ^from_id))

    List.flatten([owned, moved, repeated, vetoes, listing, gone])
  end

  defp ownerships(repo, from_id, into_id) do
    kept = repo.all(from o in Ownership, where: o.release_id == ^into_id)

    for moved <- repo.all(from o in Ownership, where: o.release_id == ^from_id) do
      case Enum.find(
             kept,
             &(&1.user_id == moved.user_id and &1.ownership_type == moved.ownership_type)
           ) do
        nil ->
          move(repo, from(o in Ownership, where: o.id == ^moved.id), release_id: into_id)

        same ->
          gone = delete(repo, from(o in Ownership, where: o.id == ^moved.id))

          repo.update_all(from(o in Ownership, where: o.id == ^same.id),
            set: [
              purchase_id: same.purchase_id || moved.purchase_id,
              acquired_at: Enum.min([same.acquired_at, moved.acquired_at], DateTime)
            ]
          )

          # The kept ownership points to the deleted one's purchase until it is back.
          [
            gone,
            {:set, Ownership, [same.id],
             [purchase_id: same.purchase_id, acquired_at: same.acquired_at]}
          ]
      end
    end
  end

  # Two listings of the same release cannot share an nsuid (unique per store), so the
  # one left behind sells another product and its prices go with it.
  defp listing(repo, from_id, into_id) do
    kept = repo.get_by(StoreListing, release_id: into_id, store: :eshop_br)
    moved = repo.get_by(StoreListing, release_id: from_id, store: :eshop_br)

    cond do
      is_nil(moved) ->
        []

      is_nil(kept) ->
        move(repo, from(l in StoreListing, where: l.id == ^moved.id), release_id: into_id)

      kept.match in [:review, :rejected] and moved.match in [:auto, :confirmed] ->
        gone = delete_listing(repo, kept)
        [gone, move(repo, from(l in StoreListing, where: l.id == ^moved.id), release_id: into_id)]

      true ->
        delete_listing(repo, moved)
    end
  end

  # The prices go with the listing (on delete cascade); they come back with it.
  defp delete_listing(repo, listing) do
    prices = repo.all(from p in StorePrice, where: p.listing_id == ^listing.id)
    gone = delete(repo, from(l in StoreListing, where: l.id == ^listing.id))
    [gone, {:insert, StorePrice, Enum.map(prices, &row/1)}]
  end

  @doc """
  One entry per account: the state of the entry changed last (intent, play state,
  backlog), the higher priority, the lower target price and both notes.
  """
  def entries(repo, winner_id, loser_id) do
    ops =
      for moved <- repo.all(from e in Entry, where: e.game_id == ^loser_id) do
        case repo.get_by(Entry, game_id: winner_id, user_id: moved.user_id) do
          nil ->
            move(repo, from(e in Entry, where: e.id == ^moved.id), game_id: winner_id)

          kept ->
            gone = delete(repo, from(e in Entry, where: e.id == ^moved.id))
            joined = joined_entry(kept, moved)
            repo.update_all(from(e in Entry, where: e.id == ^kept.id), set: joined)

            [
              gone,
              {:set, Entry, [kept.id], Enum.map(joined, fn {k, _} -> {k, Map.get(kept, k)} end)}
            ]
        end
      end

    {:ok, List.flatten(ops)}
  end

  defp joined_entry(kept, moved) do
    newer = if DateTime.compare(moved.updated_at, kept.updated_at) == :gt, do: moved, else: kept

    [
      purchase_intent: newer.purchase_intent,
      play_state: newer.play_state,
      backlog: newer.backlog,
      priority:
        Enum.max_by(
          [kept.priority, moved.priority],
          &Enum.find_index(@priorities, fn p -> p == &1 end)
        ),
      target_price_cents:
        [kept.target_price_cents, moved.target_price_cents]
        |> Enum.reject(&is_nil/1)
        |> Enum.min(fn -> nil end),
      owned_elsewhere: kept.owned_elsewhere or moved.owned_elsewhere,
      owned_elsewhere_note: kept.owned_elsewhere_note || moved.owned_elsewhere_note,
      notes:
        [kept.notes, moved.notes]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.uniq()
        |> join_notes(),
      updated_at: Enum.max([kept.updated_at, moved.updated_at], DateTime)
    ]
  end

  defp join_notes([]), do: nil
  defp join_notes(notes), do: Enum.join(notes, "\n")

  @doc """
  The game's history and links follow the winner, the loser goes, and its IGDB id
  becomes the winner's link. A link that asked about the loser gets the answer.
  """
  def game(repo, winner_id, %Game{} = loser, link) do
    events = move(repo, from(e in Event, where: e.game_id == ^loser.id), game_id: winner_id)
    links = move(repo, from(l in GameLink, where: l.game_id == ^loser.id), game_id: winner_id)
    gone = delete(repo, from(g in Game, where: g.id == ^loser.id))

    {:ok, List.flatten([events, links, gone, identity(repo, winner_id, loser, link)])}
  end

  defp identity(_repo, _winner_id, %Game{igdb_id: nil}, _link), do: []

  defp identity(repo, winner_id, %Game{igdb_id: igdb_id}, link) do
    now = DateTime.utc_now()
    before = repo.get_by(GameLink, igdb_id: igdb_id)
    id = Ecto.UUID.generate()

    repo.insert_all(
      GameLink,
      [
        %{
          id: id,
          igdb_id: igdb_id,
          game_id: winner_id,
          kind: link.kind,
          match: link.match,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [set: [game_id: winner_id, match: link.match, updated_at: now]],
      conflict_target: :igdb_id
    )

    case before do
      nil ->
        [{:delete, GameLink, [id]}]

      before ->
        [
          {:set, GameLink, [before.id],
           [game_id: before.game_id, match: before.match, updated_at: before.updated_at]}
        ]
    end
  end

  @doc "Puts back what the operations of a merge changed, last change first."
  def undo(repo, ops) do
    ops
    |> Enum.reverse()
    |> Enum.each(fn
      {:set, schema, ids, fields} ->
        repo.update_all(where(schema, [x], x.id in ^ids), set: fields)

      {:insert, _schema, []} ->
        :ok

      {:insert, schema, rows} ->
        repo.insert_all(schema, rows)

      {:delete, schema, ids} ->
        repo.delete_all(where(schema, [x], x.id in ^ids))
    end)

    {:ok, :undone}
  end

  # Points the rows of `query` elsewhere, and says how to point them back.
  defp move(repo, query, [{field, value}]) do
    before = repo.all(select(query, [x], {x.id, field(x, ^field)}))
    repo.update_all(query, set: [{field, value}])

    before
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.map(fn {old, ids} -> {:set, query_schema(query), ids, [{field, old}]} end)
  end

  defp delete(repo, query) do
    rows = repo.all(query)
    repo.delete_all(query)
    {:insert, query_schema(query), Enum.map(rows, &row/1)}
  end

  defp row(%schema{} = struct), do: Map.take(struct, schema.__schema__(:fields))

  defp query_schema(%Ecto.Query{from: %{source: {_table, schema}}}), do: schema
end
