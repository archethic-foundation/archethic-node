defmodule ArchethicWeb.Explorer.NodeListLive do
  @moduledoc false

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.P2P
  alias Archethic.PubSub

  def mount(_params, _session, socket) do
    nodes = P2P.list_nodes()
    authorized_nodes = P2P.authorized_nodes()
    pending_nodes = P2P.available_nodes() -- authorized_nodes

    # New joiners is a node which is not consired as available and never was authorized either
    new_nodes = Enum.filter(nodes, &(&1.available? == false and &1.authorization_date == nil))

    if connected?(socket) do
      PubSub.register_to_node_update()
    end

    new_socket =
      socket
      |> assign(:new_nodes, new_nodes)
      |> assign(:pending_nodes, pending_nodes)
      |> assign(:authorized_nodes, authorized_nodes)
      |> assign(:nb_nodes, length(nodes))

    {:ok, new_socket}
  end

  def handle_info({:node_update, _}, socket) do
    nodes = P2P.list_nodes()
    authorized_nodes = P2P.authorized_nodes()
    pending_nodes = P2P.available_nodes() -- authorized_nodes

    # New joiners is a node which is not consired as available and never was authorized either
    new_nodes = Enum.filter(nodes, &(&1.available? == false and &1.authorization_date == nil))

    new_socket =
      socket
      |> assign(:pending_nodes, pending_nodes)
      |> assign(:authorized_nodes, authorized_nodes)
      |> assign(:new_nodes, new_nodes)
      |> assign(:nb_nodes, length(nodes))

    {:noreply, new_socket}
  end
end
