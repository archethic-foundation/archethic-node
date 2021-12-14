defmodule ArchEthicWeb.BeaconChainLive do
  @moduledoc false
  use ArchEthicWeb, :live_view

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Slot.TransactionSummary
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.BeaconChain.SummaryTimer
  alias ArchEthic.Crypto
  alias ArchEthic.Election
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.GetTransactionChain
  alias ArchEthic.P2P.Message.GetBeaconSummaries
  alias ArchEthic.P2P.Message.BeaconSummaryList
  alias ArchEthic.P2P.Message.TransactionList
  alias ArchEthic.P2P.Node
  alias ArchEthic.PubSub
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthicWeb.ExplorerView
  alias Phoenix.View
  require Logger

  defp list_transaction_by_date(date = %DateTime{}) do
    Enum.reduce(BeaconChain.list_subsets(), %{}, fn subset, acc ->
      b_address = Crypto.derive_beacon_chain_address(subset, date, true)
      node_list = P2P.authorized_nodes()
      nodes = Election.beacon_storage_nodes(subset, date, node_list)

      Enum.reduce(nodes, acc, fn node, acc ->
        Map.update(acc, node, [b_address], &[b_address | &1])
      end)
    end)
    |> Stream.transform([], fn
      {_, []}, acc ->
        {[], acc}

      {node, addresses}, acc ->
        addresses_to_fetch = Enum.reject(addresses, &(&1 in acc))

        case P2P.send_message(node, %GetBeaconSummaries{addresses: addresses_to_fetch}) do
          {:ok, %BeaconSummaryList{summaries: summaries}} ->
            summaries_address_resolved =
              Enum.map(
                summaries,
                &Crypto.derive_beacon_chain_address(&1.subset, &1.summary_time, true)
              )

            {summaries, acc ++ summaries_address_resolved}

          _ ->
            {[], acc}
        end
    end)
    |> Stream.map(fn %BeaconSummary{transaction_summaries: transaction_summaries} ->
      transaction_summaries
    end)
    |> Stream.flat_map(& &1)
    |> Enum.to_list()
  end

  defp list_transaction_by_date(nil), do: []

  defp list_transaction_by_date_from_tx_chain(date = %DateTime{}) do
    Enum.map(BeaconChain.list_subsets(), fn subset ->
      b_address = Crypto.derive_beacon_chain_address(subset, date, true)
      node_list = P2P.authorized_nodes()
      nodes = Election.beacon_storage_nodes(subset, date, node_list)
      %Node{network_patch: patch} = P2P.get_node_info()

      {b_address, nodes, patch}
    end)
    |> Task.async_stream(
      fn {address, nodes, patch} ->
        get_beacon_summary_transaction_chain(address, nodes, patch)
      end,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Enum.filter(&match?({:ok, {:ok, _}}, &1))
    |> Enum.map(fn {:ok, {:ok, tx_list}} ->
      Enum.map(tx_list, fn %Transaction{data: %TransactionData{content: content}} ->
        {slot, _} = Slot.deserialize(content)
        %Slot{transaction_summaries: transaction_summaries} = slot
        transaction_summaries
      end)
    end)
    |> :lists.flatten()
  end

  # defp list_transaction_by_date_from_tx_chain(nil), do: []

  def mount(_params, _session, socket) do
    next_summary_time = BeaconChain.next_summary_date(DateTime.utc_now())

    if connected?(socket) do
      PubSub.register_to_next_summary_time()
      # register for client to able to get the current added transaction to the beacon pool
      PubSub.register_to_added_new_transaction_summary()
      PubSub.register_to_current_epoch_of_slot_time()
    end

    beacon_dates =
      case get_beacon_dates() |> Enum.to_list() do
        [] ->
          [next_summary_time]

        dates ->
          [next_summary_time | dates]
      end

    transactions = list_transaction_by_date_from_tx_chain(next_summary_time)

    new_assign =
      socket
      |> assign(:update_time, DateTime.utc_now())
      |> assign(:next_summary_time, next_summary_time)
      |> assign(:dates, beacon_dates)
      |> assign(:current_date_page, 1)
      |> assign(
        :transactions,
        transactions
      )

    {:ok, new_assign}
  end

  def render(assigns) do
    View.render(ExplorerView, "beacon_chain_index.html", assigns)
  end

  def handle_params(%{"page" => page}, _uri, socket = %{assigns: %{dates: dates}}) do
    case Integer.parse(page) do
      {number, ""} when number > 0 and is_list(dates) ->
        if number > length(dates) do
          {:noreply,
           push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}
        else
          transactions =
            if Enum.at(dates, 0) == Enum.at(dates, number - 1) do
              dates
              |> Enum.at(number - 1)
              |> list_transaction_by_date_from_tx_chain()
            else
              dates
              |> Enum.at(number - 1)
              |> list_transaction_by_date()
            end

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

  @spec handle_event(<<_::32>>, map, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("goto", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_info(
        {:added_new_transaction_summary, tx_summary = %TransactionSummary{}},
        socket = %{
          assigns:
            assigns = %{
              current_date_page: page,
              transactions: transactions
            }
        }
      ) do
    new_assign =
      socket
      |> assign(:update_time, DateTime.utc_now())

    if page == 1 and !Enum.member?(transactions, tx_summary) do
      # Only update the transaction listed when you are on the first page
      new_assign =
        case Map.get(assigns, :summary_passed?) do
          true ->
            new_assign
            |> assign(:transactions, [tx_summary | transactions])
            |> assign(:summary_passed?, false)

          _ ->
            update(
              new_assign,
              :transactions,
              &[tx_summary | &1]
            )
        end

      {:noreply, new_assign}
    else
      {:noreply, new_assign}
    end
  end

  def handle_info(
        {:next_summary_time, next_summary_date},
        socket = %{
          assigns: %{
            current_date_page: page,
            dates: dates
          }
        }
      ) do
    new_next_summary =
      if :gt == DateTime.compare(next_summary_date, DateTime.utc_now()) do
        next_summary_date
      else
        BeaconChain.next_summary_date(DateTime.utc_now())
      end

    new_dates = [new_next_summary | dates]

    transactions =
      new_dates
      |> Enum.at(page - 1)
      |> list_transaction_by_date()

    new_assign =
      socket
      |> assign(:transactions, transactions)
      |> assign(:dates, new_dates)
      |> assign(:next_summary_time, new_next_summary)

    {:noreply, new_assign}
  end

  def handle_info({:current_epoch_of_slot_timer, date}, socket) do
    date
    |> BeaconChain.register_to_beacon_pool_updates()

    {:noreply, socket}
  end

  defp get_beacon_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes() |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime}) |> Enum.at(0)

    enrollment_date
    |> SummaryTimer.previous_summaries()
    |> Enum.sort({:desc, DateTime})
  end

  defp get_beacon_summary_transaction_chain(_beacon_address, [], _), do: {:ok, %NotFound{}}

  defp get_beacon_summary_transaction_chain(beacon_address, nodes, patch) do
    nodes
    |> P2P.nearest_nodes(patch)
    |> do_get_download_summary_transaction_chain(beacon_address, nil)
  end

  defp do_get_download_summary_transaction_chain([node | rest], address, prev_result) do
    case P2P.send_message(node, %GetTransactionChain{address: address}) do
      {:ok, %TransactionList{transactions: transactions}} ->
        {:ok, transactions}

      {:ok, %NotFound{}} ->
        do_get_download_summary_transaction_chain(rest, address, %NotFound{})

      {:error, _} ->
        do_get_download_summary_transaction_chain(rest, address, prev_result)
    end
  end

  defp do_get_download_summary_transaction_chain([], _, %NotFound{}), do: {:ok, %NotFound{}}
  defp do_get_download_summary_transaction_chain([], _, _), do: {:error, :network_issue}
end
