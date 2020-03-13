defmodule UnirisP2PServer do
  @moduledoc false

  defdelegate child_spec(opts), to: __MODULE__.TCPImpl
end
