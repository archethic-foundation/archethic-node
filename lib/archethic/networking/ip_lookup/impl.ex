defmodule Archethic.Networking.IPLookup.Impl do
  @moduledoc false

  @callback get_node_ip() :: {:ok, :inet.ip_address()} | {:error, any()}
end
