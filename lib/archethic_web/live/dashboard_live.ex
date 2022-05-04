defmodule ArchethicWeb.DashboardLive do
  @moduledoc """
  Live-View for Network-Metric-Dashboard
  """
  use ArchethicWeb, :live_view
  alias ArchethicWeb.DashboardView
  alias Phoenix.View

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Archethic.Metrics.Poller.monitor()
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
