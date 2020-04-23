defmodule UnirisCore.Bootstrap.IPLookup.EnvImpl do
  @moduledoc false

  @behaviour UnirisCore.Bootstrap.IPLookupImpl

  @impl true
  @spec get_ip() :: :inet.ip_address()
  def get_ip() do
    {:ok, ip} =
      System.get_env("IP", "127.0.0.1")
      |> String.to_charlist()
      |> :inet.parse_address()

    ip
  end
end
