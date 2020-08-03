defmodule UnirisWeb.TransactionListLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.View

  alias Uniris.PubSub
  alias Uniris.Storage
  alias Uniris.Transaction
  alias UnirisWeb.ExplorerView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction()
    end

    transactions = Storage.list_transactions()
    {:ok, assign(socket, transactions: transactions, page: 1)}
  end

  def render(assigns) do
    View.render(ExplorerView, "transaction_list.html", assigns)
  end

  def handle_info({:new_transaction, tx = %Transaction{}}, socket) do
    {:noreply, update(socket, :transactions, &Stream.concat(&1, [tx]))}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def handle_event("load-more", _, socket) do
    {:noreply, update(socket, :page, &(&1 + 1))}
  end
end
