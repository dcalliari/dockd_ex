defmodule DockdWeb.DockdComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import DockdWeb.DockdComponents

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
end
