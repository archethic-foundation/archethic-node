defmodule UnirisWeb.NodeLive do
  use Phoenix.LiveView

  alias UnirisCore.P2P
  alias UnirisCore.P2P.Node
  alias UnirisCore.PubSub

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_node_update()
    end

    {:ok, assign(socket, :nodes, P2P.list_nodes() |> Enum.filter(& &1.ready?))}
  end

  def render(assigns) do
    Phoenix.View.render(UnirisWeb.ExplorerView, "node_list.html", assigns)
  end

  def handle_info({:node_update, node = %Node{}}, socket) do
    new_socket =
      update(socket, :nodes, fn nodes ->
        Enum.uniq_by([node | nodes], & &1.first_public_key)
      end)

    {:noreply, new_socket}
  end
end
