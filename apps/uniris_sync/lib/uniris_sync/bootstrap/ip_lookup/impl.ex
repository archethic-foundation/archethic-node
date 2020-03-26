defmodule UnirisSync.Bootstrap.IPLookup.Impl do
  @moduledoc false

  @callback get_ip() :: :inet.ip_address()
end
