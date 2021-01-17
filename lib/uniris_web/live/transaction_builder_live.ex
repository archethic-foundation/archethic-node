defmodule UnirisWeb.TransactionBuilderLive do
  @moduledoc false

  use UnirisWeb, :live_component

  alias Phoenix.View

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    View.render(UnirisWeb.ExplorerView, "transaction_builder.html", assigns)
  end
end
