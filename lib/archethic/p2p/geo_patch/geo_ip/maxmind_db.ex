defmodule Archethic.P2P.GeoPatch.GeoIP.MaxMindDB do
  @moduledoc false

  alias Archethic.P2P.GeoPatch.GeoIP
  alias MMDB2Decoder

  use GenServer
  @vsn 1

  require Logger

  @behaviour GeoIP

  def start_link(args \\ [], opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl GenServer
  def init(_) do
    Logger.info("Initialize InMemory MaxMindDB metadata...")

    database = File.read!(Application.app_dir(:archethic, "/priv/p2p/GEOLITE2.mmdb"))

    {:ok, meta, tree, data} = MMDB2Decoder.parse_database(database)

    {:ok, {meta, tree, data}}
  end

  @impl GeoIP
  def get_coordinates(ip) when is_tuple(ip) do
    GenServer.call(__MODULE__, {:get_coordinates, ip})
  end

  @impl GeoIP
  def get_coordinates_city(ip) when is_tuple(ip) do
    GenServer.call(__MODULE__, {:get_coordinates_city, ip})
  end

  @impl GenServer
  def handle_call({:get_coordinates, ip}, _from, {meta, tree, data}) do
    case MMDB2Decoder.lookup(ip, meta, tree, data) do
      {:ok, %{"location" => %{"latitude" => lat, "longitude" => lon}}} ->
        {:reply, {lat, lon}, {meta, tree, data}}

      _ ->
        {:reply, {0.0, 0.0}, {meta, tree, data}}
    end
  end

  @impl GenServer
  def handle_call({:get_coordinates_city, ip}, _from, {meta, tree, data}) do
    case MMDB2Decoder.lookup(ip, meta, tree, data) do
      {:ok, result} ->
        lat = get_in(result, ["location", "latitude"]) || 0.0
        lon = get_in(result, ["location", "longitude"]) || 0.0
        city = get_in(result, ["city", "names", "en"]) || "unknown"
        country = get_in(result, ["country", "names", "en"]) || "unknown"

        {:reply, {lat, lon, city, country}, {meta, tree, data}}

      _ ->
        {:reply, {48.8582, 2.3387, "unknown", "unknown"}, {meta, tree, data}}
    end
  end
end
