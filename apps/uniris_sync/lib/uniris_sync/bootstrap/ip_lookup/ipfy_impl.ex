defmodule UnirisSync.Bootstrap.IPLookup.IPFYImpl do
  @moduledoc false

  @behaviour UnirisSync.Bootstrap.IPLookup.Impl

  @impl true
  def get_public_ip() do
    :inets.start()
    {:ok, {_, _,inet_addr}} = :httpc.request('http://api.ipify.org')
    :inets.stop()
    {:ok, ip} = :inet.parse_address(inet_addr)
    ip
  end
end
