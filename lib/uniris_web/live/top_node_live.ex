defmodule UnirisWeb.TopNodeLive do
  @moduledoc false
  use UnirisWeb, :live_component

  alias Phoenix.View

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.PubSub

  alias UnirisWeb.ExplorerView

  def mount(socket) do
    if connected?(socket) do
      PubSub.register_to_node_update()
    end

    {:ok, assign(socket, :nodes, top_nodes(P2P.list_nodes()))}
  end

  def render(assigns) do
    View.render(ExplorerView, "top_nodes.html", assigns)
  end

  def handle_info({:node_update, node = %Node{}}, socket) do
    new_socket =
      update(socket, :nodes, fn nodes ->
        [node | nodes]
        |> Enum.uniq_by(& &1.first_public_key)
        |> top_nodes
      end)

    {:noreply, new_socket}
  end

  defp top_nodes(nodes) do
    nodes
    |> Enum.filter(& &1.available?)
    |> Enum.sort_by(& &1.average_availability, :desc)
    |> Enum.take(10)
  end
end
