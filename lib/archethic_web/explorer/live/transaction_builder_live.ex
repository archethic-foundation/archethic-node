defmodule ArchethicWeb.Explorer.TransactionBuilderLive do
  @moduledoc false

  use ArchethicWeb.Explorer, :live_component

  alias Phoenix.View

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    View.render(ArchethicWeb.Explorer.ExplorerView, "transaction_builder.html", assigns)
  end
end
