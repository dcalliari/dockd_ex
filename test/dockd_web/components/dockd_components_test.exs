defmodule DockdWeb.DockdComponentsTest do
  use DockdWeb.ConnCase

  import Phoenix.LiveViewTest

  test "money card preserves its public attributes" do
    html =
      render_component(&DockdWeb.DockdComponents.money_card/1, %{
        label: "Disponível",
        value: 19_990,
        currency: "BRL"
      })

    assert html =~ "Disponível"
    assert html =~ "R$ 199,90"
    assert html =~ "tabular-nums"
  end

  test "status and platform badges preserve their labels" do
    html =
      render_component(&DockdWeb.DockdComponents.status_chip/1, %{
        label: "não iniciado",
        tone: "warning"
      })

    platform =
      render_component(&DockdWeb.DockdComponents.platform_badge/1, %{platform: :switch_2})

    assert html =~ "badge-warning"
    assert html =~ "não iniciado"
    assert platform =~ "Switch 2"
  end
end
