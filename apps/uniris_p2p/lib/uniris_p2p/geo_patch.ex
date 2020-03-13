defmodule UnirisP2P.GeoPatch do
  @moduledoc false

  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, [], {:continue, :load_geoip_lookup}}
  end

  def handle_continue(:load_geoip_lookup, state) do
    :ip2location.new(Application.app_dir(:uniris_p2p, "/priv/IP2LOCATION-LITE-DB5.BIN"))
    {:noreply, state}
  end

  def handle_call({:get_patch_from_ip, _ip}, _, state) do
    # :ip2location.query(ip)
    {:reply, compute_random_geo_patch(), state}
  end

  # ONLY FOR TEST DEV,
  # TODO REAL IMPLEMENTATION WITH IP LOOKUP
  defp compute_random_geo_patch() do
    list_char = Enum.concat([?0..?9, ?A..?F])
    Enum.take_random(list_char, 3) |> List.to_string()
  end

  @spec from_ip(:inet.ip_address()) :: binary()
  def from_ip({_, _, _, _} = ip) do
    GenServer.call(__MODULE__, {:get_patch_from_ip, ip})
  end
end
