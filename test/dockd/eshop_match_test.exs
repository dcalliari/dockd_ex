defmodule Dockd.Pricing.EshopMatchTest do
  use ExUnit.Case, async: true
  alias Dockd.Pricing.EshopMatch

  defp hit(nsuid, title, attrs \\ %{}) do
    Map.merge(
      %{
        "nsuid" => nsuid,
        "title" => title,
        "platformCode" => "NINTENDO_SWITCH",
        "eshopDetails" => %{"productType" => "TITLE"},
        "dlcType" => nil,
        "isUpgrade" => false
      },
      attrs
    )
  end

  defp classes(title, hits, platform \\ :switch),
    do: [title] |> EshopMatch.candidates(hits, platform) |> Enum.map(&{&1.hit["nsuid"], &1.class})

  test "normalizes trademarks, accents, punctuation and the Switch 2 Edition suffix" do
    assert EshopMatch.normalize(
             "The Legend of Zelda™: Tears of the Kingdom – Nintendo Switch™ 2 Edition"
           ) == "the legend of zelda tears of the kingdom"

    assert EshopMatch.normalize("Red Dead Redemption: Edição Nintendo Switch™ 2") ==
             "red dead redemption"

    assert EshopMatch.normalize("Pokémon™ Legends: Arceus") == "pokemon legends arceus"
    assert EshopMatch.normalize("Kingdom Hearts III") == "kingdom hearts 3"
  end

  test "an alternative name that only abbreviates the title is not searched" do
    assert EshopMatch.search_titles("Mouse: P.I. for Hire", [
             "Mouse",
             "Mouse PI for Hire",
             "MOUSE: P.I. For Hire"
           ]) == ["Mouse: P.I. for Hire", "Mouse PI for Hire"]
  end

  test "edition suffixes name the same game, other suffixes do not" do
    assert classes("Rayman Legends", [hit("1", "Rayman® Legends Definitive Edition")]) ==
             [{"1", :edition}]

    assert classes("Borderlands 3", [hit("2", "Borderlands 3: Edição Ultimate")]) ==
             [{"2", :edition}]

    assert classes("Yakuza 0", [hit("3", "Yakuza 0 Director's Cut")]) == [{"3", :edition}]

    assert classes("Final Fantasy XV", [hit("4", "FINAL FANTASY XV POCKET EDITION HD")]) ==
             [{"4", :prefix}]
  end

  test "a weak candidate shares most of the game's words, not just one" do
    hits = [
      hit("1", "TSUKIHIME -A piece of blue glass moon-"),
      hit("2", "Blue Fire"),
      hit("3", "Blue Prince Deluxe Soundtrack Bundle")
    ]

    assert classes("Blue Prince", hits) == [{"3", :prefix}]

    assert classes("Borderlands 2", [hit("4", "Borderlands 3: Edição Ultimate")]) == [
             {"4", :weak}
           ]
  end

  test "extra content never becomes a game" do
    hits = [
      hit("70050000056960", "Pacote de melhoria Zelda", %{
        "eshopDetails" => %{"productType" => "ADD_ON_CONTENT"},
        "isUpgrade" => true
      }),
      hit("70070000039287", "Zelda - Platinum Edition", %{
        "eshopDetails" => %{"productType" => "BUNDLE"},
        "dlcType" => "ROM Bundle"
      }),
      hit("70050000000001", "Zelda")
    ]

    assert classes("Zelda", hits) == []
  end

  test "only the release's platform is a candidate" do
    hits = [
      hit("70010000063714", "Zelda"),
      hit("70010000096821", "Zelda – Nintendo Switch 2 Edition", %{
        "platformCode" => "NINTENDO_SWITCH_2"
      })
    ]

    assert classes("Zelda", hits, :switch) == [{"70010000063714", :exact}]
    assert classes("Zelda", hits, :switch_2) == [{"70010000096821", :exact}]
  end

  test "accepts a single safe title, preferring it over a bundle of the same name" do
    title = hit("1", "Game")
    bundle = hit("2", "Game", %{"eshopDetails" => %{"productType" => "BUNDLE"}})

    assert {:auto, %{hit: ^title}} =
             EshopMatch.decide(EshopMatch.candidates(["Game"], [bundle, title], :switch))

    assert {:review, [_, _]} =
             EshopMatch.decide(
               EshopMatch.candidates(["Game"], [title, hit("3", "Game")], :switch)
             )

    assert {:review, [%{class: :prefix}]} =
             EshopMatch.decide(
               EshopMatch.candidates(["Game"], [hit("4", "Game: Sequel")], :switch)
             )

    assert EshopMatch.decide([]) == :none
  end

  test "an edition is named as the store sells it, without the game's title" do
    titles = ["Tony Hawk's Pro Skater 3 + 4", "Tony Hawk's™ Pro Skater™ 3 + 4"]

    assert EshopMatch.edition_name(
             "Tony Hawk's™ Pro Skater™ 3 + 4 - Edição Digital Deluxe",
             titles
           ) ==
             "Edição Digital Deluxe"

    assert EshopMatch.edition_name("Hogwarts Legacy: Edição Digital Deluxe", ["Hogwarts Legacy"]) ==
             "Edição Digital Deluxe"

    assert EshopMatch.edition_name(
             "Teenage Mutant Ninja Turtles: Splintered Fate Pacote DLC com todos os personagens",
             ["Teenage Mutant Ninja Turtles: Splintered Fate"]
           ) == "Pacote DLC com todos os personagens"
  end

  test "a bundle named after the game alone is the game with extra content" do
    titles = ["Tony Hawk's Pro Skater 3 + 4"]

    assert EshopMatch.edition_name("Tony Hawk's™ Pro Skater™ 3 + 4 - Edição Padrão", titles) ==
             "Com conteúdo extra"

    assert EshopMatch.edition_name("It Takes Two", ["It Takes Two"]) == "Com conteúdo extra"

    assert EshopMatch.edition_name(
             "Pacote Animal Crossing™: New Horizons (Jogo + conteúdo extra)",
             ["Animal Crossing: New Horizons"]
           ) == "Com conteúdo extra"

    # A bundle that repeats the game's title before its content keeps only the content.
    assert EshopMatch.edition_name(
             "The Legend of Zelda™: Breath of the Wild and The Legend of Zelda™: Breath of the Wild Expansion Pass Bundle  ",
             ["The Legend of Zelda: Breath of the Wild"]
           ) == "Expansion Pass Bundle"

    assert EshopMatch.edition_name(
             "Cadence of Hyrule: Crypt of the NecroDancer featuring The Legend of Zelda + Cadence of Hyrule Season Pass",
             [
               "Cadence of Hyrule",
               "Cadence of Hyrule: Crypt of the NecroDancer Featuring The Legend of Zelda"
             ]
           ) == "Season Pass"

    assert EshopMatch.edition_name("Denshattack! Digital Deluxe Edition", ["Denshattack!"]) ==
             "Digital Deluxe Edition"

    # The game's title in the middle: what follows it names the edition.
    splinter = ["Splintered Fate", "Tartarugas Ninja O Destino de Splinter"]

    assert EshopMatch.edition_name(
             "Teenage Mutant Ninja Turtles: Splintered Fate Pacote DLC com todos os personagens",
             splinter
           ) == "Pacote DLC com todos os personagens"

    assert EshopMatch.edition_name(
             "Tartarugas Ninja: O Destino de Splinter e Casey Jones",
             splinter
           ) ==
             "Casey Jones"

    assert EshopMatch.edition_name(
             "Tartarugas Ninja: O Destino de Splinter - Edição Ouro",
             splinter
           ) ==
             "Edição Ouro"

    # A word that only starts the same is not the game's title.
    assert EshopMatch.edition_name("Cupheads Deluxe", ["Cuphead"]) == "Cupheads Deluxe"
  end
end
