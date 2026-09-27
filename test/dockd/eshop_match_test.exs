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
end
