defmodule UnirisWeb.ExplorerIndexLive do
  @moduledoc false

  use UnirisWeb, :live_view

  alias Phoenix.View

  alias UnirisWeb.ExplorerView

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    View.render(ExplorerView, "index.html", assigns)
  end

  def handle_event("search", %{"address" => address}, socket) do
    {:noreply, redirect(socket, to: "/explorer/transaction/#{address}")}
  end
end
