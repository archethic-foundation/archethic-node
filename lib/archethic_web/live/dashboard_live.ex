defmodule ArchEthicWeb.DashboardLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """
  use ArchEthicWeb, :live_view
  alias ArchEthicWeb.DashboardView
  alias Phoenix.View

  def mount(_params, _session, socket) do
    if connected?(socket) do
      ArchEthic.Metrics.Poller.monitor()
    end

    {:ok, socket}
  end

  def handle_info({:update_data, data}, socket) do
    {:noreply, socket |> push_event("network_points", %{points: data})}
  end

  def render(assigns) do
    View.render(DashboardView, "dashboard.html", assigns)
  end
end
