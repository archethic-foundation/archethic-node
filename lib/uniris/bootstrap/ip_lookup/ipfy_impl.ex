defmodule Uniris.Bootstrap.IPLookup.IPFYImpl do
  @moduledoc false

  alias Uniris.Bootstrap.IPLookupImpl

  @behaviour IPLookupImpl

  @impl IPLookupImpl
  @spec get_ip() :: :inet.ip_address()
  def get_ip do
    {:ok, {_, _, inet_addr}} = :httpc.request('http://api.ipify.org')
    :inets.stop()
    {:ok, ip} = :inet.parse_address(inet_addr)
    ip
  end
end
