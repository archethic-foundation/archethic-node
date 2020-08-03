defmodule Uniris.Bootstrap.IPLookup.LocalImpl do
  @moduledoc false

  @behaviour Uniris.Bootstrap.IPLookupImpl

  @impl true
  @spec get_ip() :: :inet.ip_address()
  def get_ip do
    local_interface =
      Application.get_env(:uniris, Uniris.Bootstrap)
      |> Keyword.fetch!(:interface)
      |> String.to_charlist()

    {:ok, address} = :inet.getifaddrs()

    {_, ip} =
      address
      |> Enum.map(fn {interface, opts} -> {interface, Keyword.get(opts, :addr)} end)
      |> Enum.find(fn {interface, _ip} -> interface == local_interface end)

    ip
  end
end
