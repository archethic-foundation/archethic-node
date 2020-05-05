defmodule UnirisWeb.TransactionLive do
  use Phoenix.LiveView

  alias UnirisCore.Transaction
  alias UnirisCore.Storage
  alias UnirisCore.PubSub

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction()
    end

    transactions =
      Storage.list_transactions()
      |> Enum.reject(&(&1.type == :beacon))
      |> Enum.sort_by(& &1.timestamp, :desc)

    {:ok, assign(socket, transactions: transactions)}
  end

  def render(assigns) do
    Phoenix.View.render(UnirisWeb.ExplorerView, "transaction_summary.html", assigns)
  end

  def handle_info({:new_transaction, tx = %Transaction{type: :beacon}}, socket),
    do: {:noreply, socket}

  def handle_info({:new_transaction, tx = %Transaction{}}, socket) do
    new_socket =
      update(socket, :transactions, fn transactions ->
        [ tx | transactions]
        |> Enum.sort_by(& &1.timestamp, :desc)
      end)

    {:noreply, new_socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
