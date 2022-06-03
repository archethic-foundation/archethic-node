defmodule Archethic.P2P.GeoPatch.GeoIP.IP2LocationImpl do
  @moduledoc false

  alias Archethic.P2P.GeoPatch.GeoIP
  alias MMDB2Decoder

  use GenServer

  require Logger

  @behaviour GeoIP
  @metadata_table :metadata

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl GenServer
  def init(_) do
    Logger.info("Initialize InMemory IP2Location metadata...")

    :ets.new(@metadata_table, [:named_table, :protected, read_concurrency: true])

    database = File.read!("./priv/p2p/GEOLITE2.mmdb")
    {:ok, meta, tree, data} = MMDB2Decoder.parse_database(database)

    true = :ets.insert(@metadata_table, {:metadata, meta, tree, data})

    {:ok, @metadata_table}
  end

  @impl GeoIP
  def get_coordinates(ip) when is_tuple(ip) do
    [{_, meta, tree, data}] = :ets.lookup(@metadata_table, :metadata)

    {:ok, %{"location" => %{"latitude" => lat, "longitude" => lon}}} =
      MMDB2Decoder.lookup(ip, meta, tree, data)

    {lat, lon}
  end
end
