defmodule Dockd.Catalog.Merge.Undo do
  @moduledoc """
  What a merge changed, as the operations that put it back (`Dockd.Catalog.Merge`).
  Kept by the screen that merged, for Desfazer; never stored.
  """
  @enforce_keys [:ops]
  defstruct [:ops]
end
