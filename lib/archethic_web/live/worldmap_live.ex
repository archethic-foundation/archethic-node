defmodule ArchEthicWeb.WorldMapLive do
  @moduledoc false

  use ArchEthicWeb, :live_view

  alias Phoenix.View
  alias ArchEthicWeb.NodeView
  alias ArchEthic.P2P
  alias ArchEthic.PubSub
  alias ArchEthic.P2P.Node
  alias ArchEthic.P2P.GeoPatch.GeoIP

  @type worldmap_data :: %{
          geo_patch: binary(),
          coords: %{
            lat: list(float()),
            lon: list(float())
          },
          nb_of_nodes: pos_integer()
        }

  @spec get_nodes_data() :: list(worldmap_data())
  defp get_nodes_data() do
    # Local nodes have a random geo_patch. To have a consistent map
    # we force a specific geo_patch for them
    P2P.available_nodes()
    |> Enum.map(fn node ->
      case GeoIP.get_coordinates(node.ip) do
        {0.0, 0.0} ->
          %Node{geo_patch: "021", authorized?: node.authorized?}

        _ ->
          node
      end
    end)
    |> Enum.frequencies_by(fn node -> {node.geo_patch, node.authorized?} end)
    |> Enum.map(fn {{geo_patch, authorized}, nb_of_nodes} ->
      with {lat, lon} <- P2P.get_coord_from_geo_patch(geo_patch) do
        %{
          geo_patch: geo_patch,
          coords: %{
            lat: Tuple.to_list(lat),
            lon: Tuple.to_list(lon)
          },
          nb_of_nodes: nb_of_nodes,
          authorized: authorized
        }
      end
    end)
  end

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_node_update()
    end

    {:ok, socket |> push_event("worldmap_init_datas", %{worldmap_datas: get_nodes_data()})}
  end

  def render(assigns) do
    View.render(NodeView, "worldmap.html", assigns)
  end

  def handle_info({:node_update, _}, socket) do
    {:noreply, socket |> push_event("worldmap_update_datas", %{worldmap_datas: get_nodes_data()})}
  end
end
