defmodule Archethic.P2P.GeoPatch.GeoIP.IP2LocationImpl do
  @moduledoc false

  alias Archethic.P2P.GeoPatch.GeoIP
  alias MMDB2Decoder

  use GenServer

  require Logger

  @behaviour GeoIP

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(_) do
    Logger.info("Initialize InMemory IP2Location metadata...")

    database = File.read!("./priv/p2p/GEOLITE2.mmdb")

    {:ok, meta, tree, data} = MMDB2Decoder.parse_database(database)

    {:ok, {meta, tree, data}}
  end

  @impl GeoIP
  def get_coordinates(ip) when is_tuple(ip) do
    GenServer.call(__MODULE__, {:get_coordinates, ip})
  end

  @impl GenServer
  def handle_call({:get_coordinates, ip}, _from, {meta, tree, data}) do
    {:ok, %{"location" => %{"latitude" => lat, "longitude" => lon}}} =
      MMDB2Decoder.lookup(ip, meta, tree, data)

    {:reply, {lat, lon}, {meta, tree, data}}
  end
end
