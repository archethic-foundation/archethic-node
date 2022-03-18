defmodule ArchEthicWeb.OracleChainLive do
  @moduledoc false

  use ArchEthicWeb, :live_view

  alias ArchEthic.Crypto

  alias ArchEthic.PubSub

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.OracleChain

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthicWeb.ExplorerView

  alias Phoenix.View

  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(:oracle)
      PubSub.register_to_new_transaction_by_type(:oracle_summary)
    end

    next_summary_date = OracleChain.next_summary_date(DateTime.utc_now())

    last_tx =
      TransactionChain.list_transactions_by_type(:oracle,
        data: [:content],
        validation_stamp: [:timestamp]
      )
      |> Enum.at(0)

    {last_oracle_data, update_time} =
      case last_tx do
        nil ->
          {%{}, nil}

        %Transaction{
          data: %TransactionData{content: content},
          validation_stamp: %ValidationStamp{timestamp: timestamp}
        } ->
          {Jason.decode!(content), timestamp}
      end

    oracle_dates =
      case get_oracle_dates() |> Enum.to_list() do
        [] ->
          [next_summary_date]

        dates ->
          [next_summary_date | dates]
      end

    new_assign =
      socket
      |> assign(:last_oracle_data, last_oracle_data)
      |> assign(:update_time, update_time || next_summary_date)
      |> assign(:dates, oracle_dates)
      |> assign(:current_date_page, 1)
      |> assign(:transactions, list_transactions_by_date(next_summary_date))

    {:ok, new_assign}
  end

  def render(assigns) do
    View.render(ExplorerView, "oracle_chain_index.html", assigns)
  end

  def handle_params(%{"page" => page}, _uri, socket = %{assigns: %{dates: dates}}) do
    case Integer.parse(page) do
      {number, ""} when number > 0 ->
        if number > length(dates) do
          {:noreply,
           push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}
        else
          transactions =
            dates
            |> Enum.at(number - 1)
            |> list_transactions_by_date()

          new_assign =
            socket
            |> assign(:current_date_page, number)
            |> assign(:transactions, transactions)

          {:noreply, new_assign}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(%{}, _, socket) do
    {:noreply, socket}
  end

  def handle_event("goto", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_info(
        {:new_transaction, address, :oracle, timestamp},
        socket = %{assigns: assigns = %{current_date_page: current_page}}
      ) do
    {:ok, %Transaction{data: %TransactionData{content: content}}} =
      TransactionChain.get_transaction(address, data: [:content])

    last_oracle_data = Jason.decode!(content)

    new_assign =
      socket
      |> assign(:last_oracle_data, last_oracle_data)
      |> assign(:update_time, timestamp)

    if current_page == 1 do
      # Only update the transaction listed when you are on the first page
      new_assign =
        case Map.get(assigns, :summary_passed?) do
          true ->
            new_assign
            |> assign(:transactions, [%{address: address, type: :oracle, timestamp: timestamp}])
            |> assign(:summary_passed?, false)

          _ ->
            update(
              new_assign,
              :transactions,
              &[%{address: address, type: :oracle, timestamp: timestamp} | &1]
            )
        end

      {:noreply, new_assign}
    else
      {:noreply, new_assign}
    end
  end

  def handle_info(
        {:new_transaction, address, :oracle_summary, timestamp},
        socket
      ) do
    new_assign =
      socket
      |> update(:dates, &[OracleChain.next_summary_date(timestamp) | &1])
      |> update(
        :transactions,
        &[
          %{address: address, type: :oracle_summary, timestamp: timestamp} | &1
        ]
      )
      |> assign(:summary_passed?, true)

    {:noreply, new_assign}
  end

  defp get_oracle_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes() |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime}) |> Enum.at(0)

    enrollment_date
    |> OracleChain.summary_dates()
    |> Enum.sort({:desc, DateTime})
  end

  defp list_transactions_by_date(date = %DateTime{}) do
    {oracle_chain, _paging_state} =
      date
      |> Crypto.derive_oracle_address(0)
      |> TransactionChain.get_last_address()
      |> TransactionChain.get([:address, :type, validation_stamp: [:timestamp]])

    oracle_chain
    |> Stream.map(fn %Transaction{
                       address: address,
                       type: type,
                       validation_stamp: %ValidationStamp{timestamp: timestamp}
                     } ->
      %{address: address, type: type, timestamp: timestamp}
    end)
    |> Enum.to_list()
  end

  defp list_transactions_by_date(nil), do: []
end
