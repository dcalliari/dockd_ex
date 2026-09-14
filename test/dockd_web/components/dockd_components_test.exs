defmodule DockdWeb.DockdComponentsTest do
  use DockdWeb.ConnCase

  import Phoenix.LiveViewTest

  test "parses Brazilian money inputs" do
    assert DockdWeb.DockdComponents.parse_money("199,90") == {:ok, 19_990}
    assert DockdWeb.DockdComponents.parse_money("199.90") == {:ok, 19_990}
    assert DockdWeb.DockdComponents.parse_money("1.234,56") == {:ok, 123_456}
    assert DockdWeb.DockdComponents.parse_money("") == {:ok, nil}
    assert DockdWeb.DockdComponents.parse_money("abc") == :error
  end

  test "status and platform badges preserve their labels" do
    html =
      render_component(&DockdWeb.DockdComponents.status_mark/1, %{
        label: "não iniciado",
        tone: "warning"
      })

    platform =
      render_component(&DockdWeb.DockdComponents.platform_badge/1, %{platform: :switch_2})

    assert html =~ "bg-warning"
    assert html =~ "não iniciado"
    assert platform =~ "Switch 2"
  end
end
