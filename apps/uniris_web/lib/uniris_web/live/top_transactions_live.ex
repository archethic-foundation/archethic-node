defmodule UnirisWeb.TopTransactionLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.View

  alias UnirisCore.PubSub
  alias UnirisCore.Storage
  alias UnirisCore.Transaction

  alias UnirisWeb.ExplorerView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction()
    end

    {:ok, assign(socket, transactions: get_last_10(Storage.list_transactions()))}
  end

  def render(assigns) do
    View.render(ExplorerView, "top_transactions.html", assigns)
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, socket) do
    {:noreply, update(socket, :transactions, &get_last_10([tx | &1]))}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp get_last_10(transactions) do
    transactions
    |> Enum.reject(&(&1.type == :beacon))
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(10)
  end
end
