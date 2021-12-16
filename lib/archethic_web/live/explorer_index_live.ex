defmodule ArchEthicWeb.ExplorerIndexLive do
  @moduledoc false

  use ArchEthicWeb, :live_view

  alias Phoenix.View

  alias ArchEthic.DB
  alias ArchEthic.PubSub

  alias ArchEthicWeb.ExplorerView

  def mount(_params, _session, socket) do
    tps = DB.get_latest_tps()
    nb_transactions = DB.get_nb_transactions()

    if connected?(socket) do
      PubSub.register_to_new_tps()
    end

    new_socket =
      socket
      |> assign(:tps, tps)
      |> assign(:nb_transactions, nb_transactions)

    {:ok, new_socket}
  end

  def render(assigns) do
    View.render(ExplorerView, "index.html", assigns)
  end

  def handle_info({:new_tps, tps, nb_transactions}, socket) do
    new_socket =
      socket
      |> assign(:tps, tps)
      |> update(:nb_transactions, &(&1 + nb_transactions))

    {:noreply, new_socket}
  end

  def handle_event("search", %{"address" => address}, socket) do
    {:noreply, redirect(socket, to: "/explorer/transaction/#{address}")}
  end
end
