defmodule UnirisCore.Bootstrap.IPLookupImpl do
  @moduledoc false

  @callback get_ip() :: :inet.ip_address()
end
