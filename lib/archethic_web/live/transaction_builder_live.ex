defmodule ArchethicWeb.TransactionBuilderLive do
  @moduledoc false

  use ArchethicWeb, :live_component

  alias Phoenix.View

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    View.render(ArchethicWeb.ExplorerView, "transaction_builder.html", assigns)
  end
end
