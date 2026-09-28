defmodule DockdWeb.DockdComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import DockdWeb.DockdComponents
  alias Dockd.Pricing.CurrentPrice
  alias Dockd.Purchasing.PriceObservation

  test "money formats cents in Brazilian reais" do
    assert money(19_990) == "R$ 199,90"
    assert money(124_990) == "R$ 1.249,90"
    assert money(-5000) == "-R$ 50,00"
    assert money(nil) == nil
  end

  test "parse_money reads the formats a person types" do
    assert parse_money("199,90") == {:ok, 19_990}
    assert parse_money("1.249,90") == {:ok, 124_990}
    assert parse_money("199.90") == {:ok, 19_990}
    assert parse_money("200") == {:ok, 20_000}
    assert parse_money("") == {:ok, nil}
    assert parse_money("abc") == :error
  end

  test "relative_label speaks Portuguese" do
    today = ~D[2026-09-25]
    assert relative_label(~U[2026-09-25 10:00:00Z], today) == "hoje"
    assert relative_label(~U[2026-09-24 10:00:00Z], today) == "ontem"
    assert relative_label(~U[2026-09-22 10:00:00Z], today) == "há 3 dias"
    assert relative_label(~U[2026-07-01 10:00:00Z], today) == "há 2 meses"
    assert relative_label(~U[2024-01-01 10:00:00Z], today) == "há 2 anos"
  end

  test "status chip renders the five states with their fills" do
    for {status, label} <- [
          quero: "Quero",
          backlog: "Backlog",
          jogando: "Jogando",
          zerado: "Zerado",
          larguei: "Larguei"
        ] do
      html = render_component(&status_chip/1, %{status: status})
      assert html =~ "dk-status--#{status}"
      assert html =~ label
    end
  end

  test "date block respects precision and marks the next two weeks" do
    today = ~D[2026-09-25]
    soon = render_component(&date_block/1, %{date: ~D[2026-10-08], precision: :day, today: today})
    assert soon =~ "dk-date--soon"
    assert soon =~ "<b>08</b><small>out</small>"

    later =
      render_component(&date_block/1, %{date: ~D[2027-02-25], precision: :day, today: today})

    refute later =~ "dk-date--soon"

    year =
      render_component(&date_block/1, %{date: ~D[2027-01-01], precision: :year, today: today})

    assert year =~ "dk-date--year"
    assert year =~ "<b>2027</b>"

    quarter =
      render_component(&date_block/1, %{date: ~D[2027-04-01], precision: :quarter, today: today})

    assert quarter =~ "<b>abr</b><small>2027</small>"
  end

  describe "price/1" do
    @now ~U[2026-09-28 12:00:00Z]

    test "strikes the full price and shows the promotion's end date" do
      observation = %CurrentPrice{
        price_cents: 3_997,
        regular_cents: 15_990,
        discount_ends_at: ~U[2026-10-17 06:59:59Z],
        currency: "BRL",
        observed_at: @now
      }

      html = render_component(&price/1, %{observation: observation, now: @now})

      assert html =~ "<s>R$ 159,90</s>"
      assert html =~ "<b>R$ 39,97</b>"
      assert html =~ "até 17/10"
      refute html =~ "menor preço"
    end

    test "shows the lowest price since Dockd started watching it, alone" do
      observation = %CurrentPrice{
        price_cents: 27_990,
        currency: "BRL",
        observed_at: @now,
        lowest_since: ~U[2026-09-27 00:00:00Z]
      }

      html = render_component(&price/1, %{observation: observation, now: @now})

      assert html =~ "menor preço desde 27/09"
      refute html =~ "até"
      refute html =~ "<s>"
    end

    test "combines the promotion and the lowest mark when both hold" do
      observation = %CurrentPrice{
        price_cents: 3_997,
        regular_cents: 15_990,
        discount_ends_at: ~U[2026-10-17 06:59:59Z],
        lowest_since: ~U[2026-09-27 00:00:00Z],
        currency: "BRL",
        observed_at: @now
      }

      html = render_component(&price/1, %{observation: observation, now: @now})

      assert html =~ "até 17/10 · menor preço"
    end

    test "falls back to the observed date and source without promotion or lowest mark" do
      observation = %CurrentPrice{price_cents: 15_990, currency: "BRL", observed_at: @now}

      html = render_component(&price/1, %{observation: observation, now: @now})

      assert html =~ "visto em #{date_pt_br(@now)} · eShop"
      refute html =~ "menor preço"
      refute html =~ "até"
    end

    test "a manual observation never shows promotion or lowest text" do
      observation = %PriceObservation{
        price_cents: 35_000,
        currency: "BRL",
        observed_at: @now,
        source: "OLX",
        format: :physical
      }

      html = render_component(&price/1, %{observation: observation, now: @now})

      assert html =~ "visto em #{date_pt_br(@now)} · OLX"
      refute html =~ "menor preço"
      refute html =~ "até"
    end

    test "the stale mark only applies to the baseline caption" do
      old = DateTime.add(@now, -40, :day)
      observation = %CurrentPrice{price_cents: 15_990, currency: "BRL", observed_at: old}

      html = render_component(&price/1, %{observation: observation, now: @now})

      assert html =~ "dk-price--stale"
      assert html =~ "desatualizado"
    end
  end
end
