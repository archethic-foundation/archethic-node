defmodule ArchethicWeb.RewardChainLive do
  @moduledoc false

  alias Archethic.{
    TransactionChain,
    PubSub,
    Reward
  }

  use ArchethicWeb, :live_view

  alias ArchethicWeb.{ExplorerView}
  alias Phoenix.{View}

  @display_limit 10

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(:node_rewards)
      PubSub.register_to_new_transaction_by_type(:mint_rewards)
    end

    tx_count =
      TransactionChain.count_transactions_by_type(:node_rewards) +
        TransactionChain.count_transactions_by_type(:mint_rewards)

    socket =
      socket
      |> assign(:tx_count, tx_count)
      |> assign(:nb_pages, total_pages(tx_count))
      |> assign(:current_page, 1)
      |> assign(:transactions, transactions_from_page(1, tx_count))

    {:ok, socket}
  end

  @spec render(Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    View.render(ExplorerView, "reward_chain_index.html", assigns)
  end

  @spec handle_params(map(), binary(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(
        %{"page" => page},
        _uri,
        socket = %{assigns: %{nb_pages: nb_pages, tx_count: tx_count}}
      ) do
    case Integer.parse(page) do
      {number, ""} when number > 0 and number > nb_pages ->
        {:noreply,
         push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}

      {number, ""} when number > 0 and number <= nb_pages ->
        socket =
          socket
          |> assign(:current_page, number)
          |> assign(:transactions, transactions_from_page(number, tx_count))

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  @spec handle_event(binary(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event(_event = "prev_page", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_event(_event = "next_page", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  @spec handle_info(
          {:new_transaction, binary(), :mint_rewards | :node_rewards, DateTime.t()},
          socket :: Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(
        {:new_transaction, address, type, timestamp},
        socket
      ) do
    {:noreply, handle_new_transaction({address, type, timestamp}, socket)}
  end

  def handle_new_transaction(
        {address, type, timestamp},
        socket = %{assigns: %{current_page: current_page, transactions: txs, tx_count: tx_count}}
      ) do
    display_txs = Enum.count(txs)

    case current_page do
      1 when display_txs < @display_limit ->
        socket
        |> assign(:tx_count, tx_count + 1)
        |> assign(:current_page, 1)
        |> update(:transactions, &[%{address: address, type: type, timestamp: timestamp} | &1])

      1 when display_txs >= @display_limit ->
        socket
        |> assign(:tx_count, tx_count + 1)
        |> assign(:nb_pages, total_pages(tx_count + 1))
        |> assign(:current_page, 1)
        |> assign(:transactions, [%{address: address, type: type, timestamp: timestamp}])

      _ ->
        socket
    end
  end

  @spec transactions_from_page(non_neg_integer(), non_neg_integer()) :: list(map())
  def transactions_from_page(current_page, tx_count) do
    nb_drops = tx_count - current_page * @display_limit

    {nb_drops, display_limit} =
      if nb_drops < 0, do: {0, @display_limit + nb_drops}, else: {nb_drops, @display_limit}

    case Reward.genesis_address() do
      address when is_binary(address) ->
        address
        |> TransactionChain.list_chain_addresses()
        |> Stream.drop(nb_drops)
        |> Stream.take(display_limit)
        |> Stream.map(fn {addr, timestamp} ->
          %{
            address: addr,
            type: (TransactionChain.get_transaction(addr, [:type]) |> elem(1)).type,
            timestamp: DateTime.from_unix(timestamp, :millisecond) |> elem(1)
          }
        end)
        |> Enum.reverse()

      _ ->
        []
    end
  end

  @doc """
   Nb of pages required to display all the transactions.

   ## Examples
      iex> total_pages(45)
      5
      iex> total_pages(40)
      4
      iex> total_pages(1)
      1
      iex> total_pages(10)
      1
      iex> total_pages(11)
      2
      iex> total_pages(0)
      0
  """
  @spec total_pages(tx_count :: non_neg_integer()) ::
          non_neg_integer()
  def total_pages(tx_count) when rem(tx_count, @display_limit) == 0,
    do: count_pages(tx_count)

  def total_pages(tx_count), do: count_pages(tx_count) + 1

  def count_pages(tx_count), do: div(tx_count, @display_limit)
end
