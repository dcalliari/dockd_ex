defmodule Dockd.Catalog.IgdbFamily do
  @moduledoc """
  What an IGDB entry is to another one, from the signals IGDB gives:

    * `:version`: an edition of the parent (`version_parent`), Deluxe, Complete, GOTY;
    * `:switch_2_edition`: the parent's Nintendo Switch 2 Edition, an expanded game
      (`game_type` 10) or port (11) sold only on Switch 2 under that name;
    * `:remaster` (9), `:expanded` (10), `:port` (11): maybe the same game, maybe not
      ("Definitive", "Anniversary", "Remastered"); a person decides;
    * anything else, remakes (8) included, is a game of its own.

  Only `:version` and `:switch_2_edition` join the parent without asking. Either way the
  parent must be sold on a Nintendo platform: when it is not, the child is the only way
  to play it there, and is the game.
  """

  @automatic [:version, :switch_2_edition]
  @doubtful %{9 => :remaster, 10 => :expanded, 11 => :port}

  @doc """
  `{kind, parent_igdb_id}` for an entry that is an edition or child of another one,
  or `:own`.
  """
  def relation(%{"version_parent" => parent}) when is_integer(parent), do: {:version, parent}

  def relation(%{"parent_game" => parent, "game_type" => type} = entry)
      when is_integer(parent) and is_map_key(@doubtful, type) do
    if type in [10, 11] and switch_2_edition?(entry),
      do: {:switch_2_edition, parent},
      else: {@doubtful[type], parent}
  end

  def relation(_entry), do: :own

  @doc "Whether a kind joins its parent without asking a person."
  def automatic?(kind), do: kind in @automatic

  @doc "Whether an entry is sold on Switch or Switch 2."
  def nintendo?(entry),
    do:
      Enum.any?(
        entry["platforms"] || [],
        &(&1["id"] in [Dockd.IGDB.switch_platform_id(), Dockd.IGDB.switch_2_platform_id()])
      )

  defp switch_2_edition?(entry) do
    platforms = Enum.map(entry["platforms"] || [], & &1["id"])

    platforms == [Dockd.IGDB.switch_2_platform_id()] and
      Regex.match?(~r/nintendo switch\W*2 edition/iu, entry["name"] || "")
  end
end
