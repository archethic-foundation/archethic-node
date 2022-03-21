defmodule ArchEthicWeb.BeaconChainLive do
  @moduledoc false
  use ArchEthicWeb, :live_view

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias ArchEthic.BeaconChain.Slot
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.BeaconChain.SummaryTimer

  alias ArchEthic.Crypto

  alias ArchEthic.Election

  alias ArchEthic.P2P
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

  def mount(_params, _session, socket) do
    next_summary_time = BeaconChain.next_summary_date(DateTime.utc_now())

    if connected?(socket) do
      PubSub.register_to_next_summary_time()
      # register for client to able to get the current added transaction to the beacon pool
      PubSub.register_to_current_epoch_of_slot_time()
      PubSub.register_to_new_replication_attestations()
    end

    beacon_dates =
      case get_beacon_dates() |> Enum.to_list() do
        [] ->
          [next_summary_time]

        dates ->
          [next_summary_time | dates]
      end

    BeaconChain.register_to_beacon_pool_updates()

    new_assign =
      socket
      |> assign(:next_summary_time, next_summary_time)
      |> assign(:dates, beacon_dates)
      |> assign(:current_date_page, 1)
      |> assign(:update_time, DateTime.utc_now())
      |> assign(
        :transactions,
        []
      )
      |> assign(:fetching, true)

    send(self(), {:initial_load, next_summary_time})
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
          new_assign =
            socket
            |> assign(:current_date_page, number)
            |> assign(:transactions, [])
            |> assign(:fetching, true)

          if Enum.at(dates, 0) == Enum.at(dates, number - 1) do
            next_summary_date =
              dates
              |> Enum.at(number - 1)

            send(self(), {:initial_load, next_summary_date})
          else
            date =
              dates
              |> Enum.at(number - 1)

            send(self(), {:load_at, date})
          end

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

  def handle_info({:initial_load, next_summary_time}, socket) do
    transactions = list_transaction_by_date_from_tx_chain(next_summary_time)

    new_socket =
      socket
      |> assign(:transactions, transactions)
      |> assign(:update_time, DateTime.utc_now())
      |> assign(:fetching, false)

    {:noreply, new_socket}
  end

  def handle_info({:load_at, date}, socket) do
    transactions = list_transaction_by_date(date)

    new_assign =
      socket
      |> assign(:fetching, false)
      |> assign(:transactions, transactions)

    {:noreply, new_assign}
  end

  def handle_info(
        {:new_replication_attestation, %ReplicationAttestation{transaction_summary: tx_summary}},
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

    if page == 1 and !Enum.any?(transactions, fn tx -> tx.address == tx_summary.address end) do
      # Only update the transaction listed when you are on the first page
      new_assign =
        case Map.get(assigns, :summary_passed?) do
          true ->
            new_assign
            |> assign(:transactions, Enum.uniq([tx_summary | transactions]))
            |> assign(:summary_passed?, false)

          _ ->
            update(
              new_assign,
              :transactions,
              &Enum.uniq([tx_summary | &1])
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

  def handle_info(
        {:current_epoch_of_slot_timer, date},
        socket
      ) do
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

  defp get_beacon_summary_transaction_chain(beacon_address, nodes, patch) do
    nodes
    |> P2P.nearest_nodes(patch)
    |> do_get_download_summary_transaction_chain(beacon_address)
  end

  defp do_get_download_summary_transaction_chain(nodes, address, opts \\ [], acc \\ [])

  defp do_get_download_summary_transaction_chain(
         nodes = [node | rest],
         address,
         opts,
         acc
       ) do
    message = %GetTransactionChain{
      address: address,
      paging_state: Keyword.get(opts, :paging_state)
    }

    case P2P.send_message(node, message) do
      {:ok, %TransactionList{transactions: transactions, more?: false}} ->
        {:ok, Enum.uniq_by(acc ++ transactions, & &1.address)}

      {:ok, %TransactionList{transactions: transactions, more?: true, paging_state: paging_state}} ->
        do_get_download_summary_transaction_chain(
          nodes,
          address,
          [paging_state: paging_state],
          Enum.uniq_by(acc ++ transactions, & &1.address)
        )

      {:error, _} ->
        do_get_download_summary_transaction_chain(
          rest,
          address,
          opts,
          acc
        )
    end
  end

  defp do_get_download_summary_transaction_chain([], _, _, _), do: {:error, :network_issue}

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
    |> Stream.map(fn %BeaconSummary{transaction_attestations: transaction_attestations} ->
      Enum.map(transaction_attestations, & &1.transaction_summary)
    end)
    |> Stream.flat_map(& &1)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp list_transaction_by_date(nil), do: []

  defp list_transaction_by_date_from_tx_chain(date = %DateTime{}) do
    %Node{network_patch: patch} = P2P.get_node_info()

    Task.async_stream(BeaconChain.list_subsets(), fn subset ->
      b_address = Crypto.derive_beacon_chain_address(subset, date, true)
      node_list = P2P.authorized_nodes()
      nodes = Election.beacon_storage_nodes(subset, date, node_list)

      {:ok, transactions} = get_beacon_summary_transaction_chain(b_address, nodes, patch)

      transactions
      |> Stream.map(&deserialize_beacon_transaction/1)
      |> Enum.to_list()
    end)
    |> Enum.map(fn {:ok, txs} -> txs end)
    |> :lists.flatten()
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp deserialize_beacon_transaction(%Transaction{data: %TransactionData{content: content}}) do
    {slot, _} = Slot.deserialize(content)
    %Slot{transaction_attestations: transaction_attestations} = slot
    Enum.map(transaction_attestations, & &1.transaction_summary)
  end
end
