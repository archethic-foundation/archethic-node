defmodule UnirisNetwork.GeoPatch do
  @moduledoc false

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, [], {:continue, :load_geoip_lookup}}
  end

  def handle_continue(:load_geoip_lookup, state) do
    :ip2location.new(Application.app_dir(:uniris_network, "/priv/IP2LOCATION-LITE-DB5.BIN"))
    {:noreply, state}
  end

  def handle_call({:get_patch_from_ip, ip}, _, state) do
    :ip2location.query(ip)
    {:reply, "000", state}
  end

  @spec from_ip(:inet.ip_address()) :: binary()
  def from_ip({_, _, _, _} = ip) do
    GenServer.call(__MODULE__, {:get_patch_from_ip, ip})
  end
end
