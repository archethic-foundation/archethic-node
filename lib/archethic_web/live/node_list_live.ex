defmodule ArchEthicWeb.NodeListLive do
  @moduledoc false

  use ArchEthicWeb, :live_view

  alias ArchEthic.P2P
  alias ArchEthic.PubSub

  alias ArchEthicWeb.NodeView

  alias Phoenix.View

  def mount(_params, _session, socket) do
    nodes = P2P.list_nodes()
    authorized_nodes = P2P.authorized_nodes()
    pending_nodes = P2P.available_nodes() -- authorized_nodes
    offline_nodes = Enum.reject(nodes, & &1.available?)

    if connected?(socket) do
      PubSub.register_to_node_update()
    end

    new_socket =
      socket
      |> assign(:pending_nodes, pending_nodes)
      |> assign(:authorized_nodes, authorized_nodes)
      |> assign(:nb_nodes, length(nodes))
      |> assign(:offline_nodes, offline_nodes)

    {:ok, new_socket}
  end

  def render(assigns) do
    View.render(NodeView, "list.html", assigns)
  end

  def handle_info({:node_update, _}, socket) do
    nodes = P2P.list_nodes()
    authorized_nodes = P2P.authorized_nodes()
    pending_nodes = P2P.available_nodes() -- authorized_nodes
    offline_nodes = Enum.reject(nodes, & &1.available?)

    new_socket =
      socket
      |> assign(:pending_nodes, pending_nodes)
      |> assign(:authorized_nodes, authorized_nodes)
      |> assign(:offline_nodes, offline_nodes)
      |> assign(:nb_nodes, length(nodes))

    {:noreply, new_socket}
  end
end
