defmodule UnirisSync.Bootstrap.IPLookup.Impl do
  @moduledoc false

  @callback get_public_ip() :: :inet.ip_address()
end
