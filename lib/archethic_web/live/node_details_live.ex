defmodule ArchEthicWeb.NodeDetailsLive do
  @moduledoc false

  use ArchEthicWeb, :live_view

  alias ArchEthic.Crypto
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  alias ArchEthic.PubSub

  alias ArchEthicWeb.NodeView

  alias Phoenix.View

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    View.render(NodeView, "details.html", assigns)
  end

  def handle_params(_params = %{"public_key" => public_key}, _uri, socket) do
    with {:ok, pub} <- Base.decode16(public_key, case: :mixed),
         true <- Crypto.valid_public_key?(pub),
         {:ok, node = %Node{last_public_key: last_public_key}} <-
           P2P.get_node_info(pub) do
      node_address = Crypto.hash(last_public_key)

      PubSub.register_to_node_update()

      new_socket =
        socket
        |> assign(:node, node)
        |> assign(:node_address, node_address)

      {:noreply, new_socket}
    else
      {:error, :not_found} ->
        {:noreply, assign(socket, :error, :not_exists)}

      _ ->
        {:noreply, assign(socket, :error, :invalid_public_key)}
    end
  end

  def handle_info(
        {:node_update, node = %Node{first_public_key: first_public_key}},
        socket = %{assigns: %{node: %Node{first_public_key: node_public_key}}}
      ) do
    if first_public_key == node_public_key do
      {:noreply, assign(socket, :node, node)}
    else
      {:noreply, socket}
    end
  end
end
