defmodule Dockd.Pricing.EshopMatch do
  @moduledoc """
  Classifies eShop search hits against a game's titles, for one platform.

  Classes, strongest first: `:exact` (same normalized title), `:edition` (same after
  dropping an edition suffix such as "Definitive Edition"), `:prefix` (the store title
  starts with the game's), `:contains` and `:weak` (most of the game's words). Only `:exact` and
  `:edition` are safe to accept without a person: a prefix can be another game
  ("Final Fantasy XV" → "Pocket Edition HD").

  Extra content never becomes a game: add-ons and upgrade packs (nsuid `7005…`,
  `isUpgrade`, "Pacote de melhoria"), and anything with a `dlcType`, bundles of game
  and DLC included.
  """

  @automatic [:exact, :edition]
  @rank %{exact: 0, edition: 1, prefix: 2, contains: 3, weak: 4}
  @platform_codes %{switch: "NINTENDO_SWITCH", switch_2: "NINTENDO_SWITCH_2"}

  # Normalized suffixes that name an edition of the same game, not another game.
  @edition_suffixes [
    "definitive edition",
    "complete edition",
    "royal edition",
    "goty edition",
    "game of the year edition",
    "deluxe edition",
    "ultimate edition",
    "gold edition",
    "standard edition",
    "special edition",
    "anniversary edition",
    "world machine edition",
    "master collection version",
    "director s cut",
    "directors cut",
    "remastered",
    "edicao definitiva",
    "edicao completa",
    "edicao padrao",
    "edicao deluxe",
    "edicao ultimate",
    "edicao especial",
    "edicao jogo do ano"
  ]

  @stop_words ~w(the of and a an o os as e de do da dos das)

  @doc """
  The titles to search and compare: the game's title and its alternative names,
  without those that only abbreviate the title ("Mouse" for "Mouse: P.I. for Hire"),
  which find every other game starting with the same word.
  """
  def search_titles(title, alternative_names) do
    main = normalize(title)

    alternatives =
      Enum.reject(alternative_names, fn name ->
        String.starts_with?(main, normalize(name) <> " ")
      end)

    Enum.uniq_by([title | alternatives], &normalize/1)
  end

  @doc "Whether a class is safe to accept without review."
  def automatic?(class), do: class in @automatic

  @doc "Whether a hit is a game or bundle sold on its own, not extra content."
  def game?(hit) do
    product_type = get_in(hit, ["eshopDetails", "productType"])
    title = hit["title"] || ""

    is_binary(hit["nsuid"]) and not String.starts_with?(hit["nsuid"], "7005") and
      product_type in [nil, "TITLE", "BUNDLE"] and is_nil(hit["dlcType"]) and
      hit["isUpgrade"] != true and
      not Regex.match?(~r/pacote de melhoria|upgrade pack/iu, title)
  end

  @doc """
  The candidates for a platform, best first: `%{hit: hit, class: class}`, in the
  store's own order within a class, titles before bundles.
  """
  def candidates(titles, hits, platform) do
    code = Map.fetch!(@platform_codes, platform)
    names = titles |> Enum.map(&normalize/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    hits
    |> Enum.filter(&(game?(&1) and &1["platformCode"] == code))
    |> Enum.uniq_by(& &1["nsuid"])
    |> Enum.with_index()
    |> Enum.flat_map(fn {hit, index} ->
      case best_class(names, normalize(hit["title"] || "")) do
        nil -> []
        class -> [{%{hit: hit, class: class}, index}]
      end
    end)
    |> Enum.sort_by(fn {%{hit: hit, class: class}, index} ->
      {@rank[class], if(bundle?(hit), do: 1, else: 0), index}
    end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Decides a platform's listing from its candidates: `{:auto, candidate}` when one
  exact or edition title stands alone at the top, `{:review, candidates}` otherwise,
  or `:none` without candidates.
  """
  def decide([]), do: :none

  def decide([%{class: class} = best | rest] = candidates) do
    tied = Enum.take_while(rest, &(&1.class == class and bundle?(&1.hit) == bundle?(best.hit)))

    if automatic?(class) and tied == [],
      do: {:auto, best},
      else: {:review, Enum.take(candidates, 3)}
  end

  defp bundle?(hit), do: get_in(hit, ["eshopDetails", "productType"]) == "BUNDLE"

  defp best_class(names, store) do
    names
    |> Enum.map(&class(&1, store))
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(&@rank[&1], fn -> nil end)
  end

  defp class(name, store) do
    cond do
      name == store -> :exact
      edition_base(name) == edition_base(store) -> :edition
      String.starts_with?(store, name <> " ") -> :prefix
      String.contains?(" " <> store <> " ", " " <> name <> " ") -> :contains
      shares_most_words?(name, store) -> :weak
      true -> nil
    end
  end

  # One shared word is noise ("Blue Prince" and "TSUKIHIME -A piece of blue glass
  # moon-"); most of the game's words make a candidate worth showing.
  defp shares_most_words?(name, store) do
    words = fn title ->
      title
      |> String.split()
      |> Enum.reject(&(&1 in @stop_words or String.length(&1) < 3))
      |> MapSet.new()
    end

    wanted = words.(name)
    shared = MapSet.intersection(wanted, words.(store))
    MapSet.size(shared) * 2 > MapSet.size(wanted)
  end

  @doc "Drops an edition suffix from a normalized title."
  def edition_base(title) do
    Enum.find_value(@edition_suffixes, title, fn suffix ->
      if String.ends_with?(title, " " <> suffix),
        do: String.trim_trailing(String.replace_suffix(title, suffix, ""))
    end)
  end

  @doc """
  Normalizes a title for comparison: no trademark signs, accents, punctuation or
  "Nintendo Switch 2 Edition", lower case, Roman numerals as digits.
  """
  def normalize(title) do
    title
    |> String.replace(["™", "®", "©"], "")
    |> String.replace("&", " and ")
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.replace(~r/\b(?:nintendo switch (?:2 )?edition|edicao nintendo switch 2)\b/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.replace(~r/\b(?:iii)\b/u, "3")
    |> String.replace(~r/\b(?:ii)\b/u, "2")
    |> String.replace(~r/\b(?:iv)\b/u, "4")
  end
end
