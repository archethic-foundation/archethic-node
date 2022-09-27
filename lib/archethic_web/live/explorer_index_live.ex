defmodule ArchethicWeb.ExplorerIndexLive do
  @moduledoc false

  use ArchethicWeb, :live_view

  alias Phoenix.View

  alias Archethic.{DB, PubSub, BeaconChain}
  alias Archethic.TransactionChain.TransactionSummary
  alias ArchethicWeb.ExplorerView
  alias ArchethicWeb.ExplorerIndexLive.TopTransactionsComponent

  def mount(_params, _session, socket) do
    tps = DB.get_latest_tps()
    nb_transactions = DB.get_nb_transactions()

    if connected?(socket) do
      PubSub.register_to_new_tps()
      PubSub.register_to_new_transaction_attestations()
      PubSub.register_to_current_epoch_of_slot_time()

      # Register to beacon pool
      Task.start(fn -> BeaconChain.register_to_beacon_pool_updates() end)
    end

    new_socket =
      socket
      |> assign(:tps, tps)
      |> assign(:nb_transactions, nb_transactions)
      |> assign(:update_time, DateTime.utc_now())
      |> assign(:transactions, [])
      |> assign(:fetching, true)

    {:ok, new_socket}
  end

  def render(assigns) do
    View.render(ExplorerView, "index.html", assigns)
  end

  def handle_info(
        {:current_epoch_of_slot_timer, date},
        socket
      ) do
    # We refresh the live feed subscription at each slot time
    BeaconChain.register_to_beacon_pool_updates(date, true)

    {:noreply, socket}
  end

  def handle_info(
        {:new_transaction_attestation, tx_summary = %TransactionSummary{}},
        socket = %{
          assigns:
            _assigns = %{
              transactions: transactions
            }
        }
      ) do
    # Only update the transactions when new transaction recieved and passed 10 transactions limit
    new_socket =
      socket
      |> assign(:transactions, Enum.take([tx_summary | transactions], 10))
      |> assign(:update_time, DateTime.utc_now())
      |> assign(:fetching, false)

    send_update(TopTransactionsComponent,
      id: "last_ten_transactions",
      transaction: tx_summary
    )

    {:noreply, new_socket}
  end

  def handle_info({:update_data, data}, socket) do
    {:noreply, socket |> push_event("explorer_stats_points", %{points: data})}
  end

  def handle_info({:new_tps, tps, nb_transactions}, socket) do
    new_socket =
      socket
      |> assign(:tps, tps)
      |> update(:nb_transactions, &(&1 + nb_transactions))

    {:noreply, new_socket}
  end

  def handle_event("search", %{"address" => address}, socket) do
    {:noreply, redirect(socket, to: "/explorer/transaction/#{address}")}
  end
end
