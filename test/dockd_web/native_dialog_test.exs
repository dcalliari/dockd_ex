defmodule DockdWeb.NativeDialogTest do
  use ExUnit.Case, async: true

  # The owner's rule (design/README.md): no browser-native dialog, ever. An irreversible
  # action confirms inside the interface.
  test "web source never opens a native browser dialog" do
    forbidden = ~r/data-confirm|window\.(confirm|alert|prompt)\b/

    source_files =
      (Path.wildcard("lib/**/*") ++ Path.wildcard("assets/js/**/*"))
      |> Enum.filter(&File.regular?/1)

    assert source_files != []

    for path <- source_files do
      refute File.read!(path) =~ forbidden, "native dialog found in #{path}"
    end
  end
end
