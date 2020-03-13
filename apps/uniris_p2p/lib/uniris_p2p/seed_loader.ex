defmodule UnirisP2P.SeedLoader do
  @moduledoc false

  defdelegate child_spec(opts), to: UnirisP2P.DefaultImpl.SeedLoader
end
