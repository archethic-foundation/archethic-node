defmodule ArchEthicWeb.TransactionBuilderLive do
  @moduledoc false

  use ArchEthicWeb, :live_component

  alias Phoenix.View

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    View.render(ArchEthicWeb.ExplorerView, "transaction_builder.html", assigns)
  end
end
