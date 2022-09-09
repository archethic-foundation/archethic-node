defmodule ArchethicWeb.TopTransactionLive do
  @moduledoc false
  use ArchethicWeb, :live_view

  alias Phoenix.View

  alias Archethic.PubSub

  alias Archethic.TransactionChain

  alias ArchethicWeb.ExplorerView

  @nb_transactions 3

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction()
    end

    transactions =
      [:address, :type, validation_stamp: [:timestamp]]
      |> TransactionChain.list_all()
      |> get_last_n(@nb_transactions)

    {:ok, assign(socket, transactions: transactions)}
  end

  def render(assigns) do
    View.render(ExplorerView, "top_transactions.html", assigns)
  end

  def handle_info({:new_transaction, address, type, timestamp}, socket) do
    new_socket =
      update(
        socket,
        :transactions,
        &(Stream.concat(&1, [%{address: address, type: type, timestamp: timestamp}])
          |> get_last_n(@nb_transactions))
      )

    {:noreply, new_socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp get_last_n(transactions, n) do
    transactions
    # |> Enum.sort_by(& &1.validation_stamp.timestamp, {:desc, DateTime})
    |> Enum.take(n)
  end
end
