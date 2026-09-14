defmodule DockdWeb.InputSafetyTest do
  use ExUnit.Case, async: true

  test "web source never converts client input to atoms" do
    forbidden = ["String.to_existing_atom", "String.to_atom"]
    source_files = Path.wildcard("lib/dockd_web/**/*") |> Enum.filter(&File.regular?/1)

    assert source_files != []

    for path <- source_files, token <- forbidden do
      refute File.read!(path) =~ token, "#{token} found in #{path}"
    end
  end
end
