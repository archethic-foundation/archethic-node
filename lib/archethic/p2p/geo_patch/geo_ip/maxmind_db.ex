defmodule Archethic.P2P.GeoPatch.GeoIP.MaxMindDB do
  @moduledoc false

  alias Archethic.P2P
  alias Archethic.P2P.GeoPatch
  alias Archethic.P2P.GeoPatch.GeoIP
  alias Archethic.P2P.MemTable
  alias Archethic.P2P.Node

  alias MMDB2Decoder
  alias MMDB2Decoder.Metadata

  use GenServer
  @vsn Mix.Project.config()[:version]

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

  @impl GenServer
  def handle_call({:get_coordinates, ip}, _from, {meta, tree, data}) do
    case MMDB2Decoder.lookup(ip, meta, tree, data) do
      {:ok, %{"location" => %{"latitude" => lat, "longitude" => lon}}} ->
        {:reply, {lat, lon}, {meta, tree, data}}

      _ ->
        {:reply, {0.0, 0.0}, {meta, tree, data}}
    end
  end

  @impl true
  def code_change(_, state = {%Metadata{build_epoch: previous_epoch}, _tree, _data, _}, _extra) do
    database = File.read!(Application.app_dir(:archethic, "/priv/p2p/GEOLITE2.mmdb"))

    {:ok, meta = %Metadata{build_epoch: build_epoch}, tree, data} =
      MMDB2Decoder.parse_database(database)

    if build_epoch > previous_epoch do
      # Update the geo patch on all the nodes
      Enum.each(P2P.list_nodes(), fn node = %Node{ip: ip} ->
        case MMDB2Decoder.lookup(ip, meta, tree, data) do
          {:ok, %{"location" => %{"latitude" => lat, "longitude" => lon}}} ->
            geo_patch = GeoPatch.compute_patch(lat, lon)
            MemTable.add_node(%{node | geo_patch: geo_patch})

          _ ->
            :skip
        end
      end)

      {:ok, {meta, tree, data}}
    else
      {:ok, state}
    end
  end
end
