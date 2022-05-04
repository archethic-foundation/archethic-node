defmodule ArchethicWeb.TransactionListLive do
  @moduledoc false
  use ArchethicWeb, :live_view

  alias Phoenix.View

  alias Archethic.PubSub

  alias Archethic.TransactionChain
  alias ArchethicWeb.ExplorerView

  @transactions_by_page 10

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction()
    end

    transactions = TransactionChain.list_all([:address, :type, :timestamp])

    {:ok,
     assign(socket,
       src_transactions: transactions,
       displayed_transactions: transactions,
       filter_type: nil,
       page: 1,
       transactions_by_page: @transactions_by_page
     )}
  end

  def render(assigns) do
    View.render(ExplorerView, "transaction_list.html", assigns)
  end

  def handle_info(
        {:new_transaction, address, type, timestamp},
        socket = %{assigns: %{src_transactions: src_transactions, filter_type: filter_type}}
      ) do
    src_transactions =
      src_transactions
      |> Stream.concat([%{address: address, type: type, timestamp: timestamp}])
      |> Enum.sort_by(& &1.validation_stamp.timestamp, {:desc, DateTime})

    displayed_transactions =
      case filter_type do
        nil ->
          src_transactions

        type ->
          filter_transactions_by_type(src_transactions, type)
      end

    new_socket =
      socket
      |> assign(:src_transactions, src_transactions)
      |> assign(:displayed_transactions, displayed_transactions)

    {:noreply, new_socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def handle_event("load-more", _, socket) do
    {:noreply, update(socket, :page, &(&1 + 1))}
  end

  def handle_event(
        "filter",
        %{"type" => type},
        socket = %{assigns: %{src_transactions: src_transactions}}
      ) do
    new_socket =
      socket
      |> assign(:filter_type, type)
      |> assign(:displayed_transactions, filter_transactions_by_type(src_transactions, type))

    {:noreply, new_socket}
  end

  defp filter_transactions_by_type(transactions, "id"),
    do: Stream.filter(transactions, &(&1.type == :id))

  defp filter_transactions_by_type(transactions, "keychain"),
    do: Stream.filter(transactions, &(&1.type == :keychain))

  defp filter_transactions_by_type(transactions, "transfer"),
    do: Stream.filter(transactions, &(&1.type == :transfer))

  defp filter_transactions_by_type(transactions, "hosting"),
    do: Stream.filter(transactions, &(&1.type == :hosting))

  defp filter_transactions_by_type(transactions, "code_proposal"),
    do: Stream.filter(transactions, &(&1.type == :code_proposal))

  defp filter_transactions_by_type(transactions, "code_approval"),
    do: Stream.filter(transactions, &(&1.type == :code_approval))

  defp filter_transactions_by_type(transactions, "node"),
    do: Stream.filter(transactions, &(&1.type == :node))

  defp filter_transactions_by_type(transactions, "node_shared_secrets"),
    do: Stream.filter(transactions, &(&1.type == :node_shared_secrets))

  defp filter_transactions_by_type(transactions, "nft"),
    do: Stream.filter(transactions, &(&1.type == :nft))

  defp filter_transactions_by_type(transactions, _), do: transactions
end
