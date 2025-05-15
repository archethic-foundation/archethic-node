defmodule ArchethicWeb.Explorer.WorldMapLive do
  @moduledoc false

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.P2P
  alias Archethic.PubSub
  # alias Archethic.P2P.Node
  alias Archethic.P2P.GeoPatch.GeoIP

  @type worldmap_data :: %{
          geo_patch: binary(),
          coords: %{
            lat: list(float()),
            lon: list(float())
          },
          nb_of_nodes: pos_integer()
        }

  @spec get_nodes_data() :: list(map())
  defp get_nodes_data() do
    Enum.map(P2P.available_nodes(), fn node ->
      case GeoIP.get_coordinates_city(node.ip) do
        {lat, lon, city, country} when lat != 0.0 or lon != 0.0 ->
          %{
            ip: Tuple.to_list(node.ip) |> Enum.join("."),
            port: node.port,
            http_port: node.http_port,
            enrollment_date: node.enrollment_date,
            first_public_key: Base.encode16(node.first_public_key, case: :lower),
            lat: lat,
            lng: lon,
            city: city,
            country: country,
            average_availability: node.average_availability,
            authorized: node.authorized?,
            global_availability: node.synced?,
            local_availability: node.available?
          }

        _ ->
          # Fallback node no geolocalisation
          %{
            ip: Tuple.to_list(node.ip) |> Enum.join("."),
            port: node.port,
            http_port: node.http_port,
            enrollment_date: node.enrollment_date,
            first_public_key: Base.encode16(node.first_public_key, case: :lower),
            lat: 48.8582,
            lng: 2.3387,
            city: "unknown",
            country: "unknown",
            average_availability: node.average_availability,
            authorized: node.authorized?,
            global_availability: node.synced?,
            local_availability: node.available?
          }
      end
    end)
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_node_update()
    end

    w_data = get_nodes_data()

    {:ok, socket |> push_event("worldmap_init_datas", %{worldmap_datas: w_data})}
  end

  def handle_info({:node_update, _}, socket) do
    w_data = get_nodes_data()

    {:noreply, socket |> push_event("worldmap_update_datas", %{worldmap_datas: w_data})}
  end
end
