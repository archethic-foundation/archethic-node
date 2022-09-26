defmodule ArchethicWeb.NodeSharedSecretsChainLive do
  @moduledoc false

  use ArchethicWeb, :live_view

  alias Archethic.{
    TransactionChain,
    PubSub,
    SharedSecrets
  }

  alias ArchethicWeb.{ExplorerView}
  alias Phoenix.{LiveView, View}

  @display_limit 10
  @txn_type :node_shared_secrets

  @spec mount(_parameters :: map(), _session :: map(), socket :: LiveView.Socket.t()) ::
          {:ok, LiveView.Socket.t()}
  def mount(_parameters, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(@txn_type)
    end

    tx_count = TransactionChain.count_transactions_by_type(@txn_type)

    socket =
      case @txn_type
           |> SharedSecrets.genesis_address() do
        nil ->
          socket
          |> assign(:tx_count, 0)
          |> assign(:nb_pages, 0)
          |> assign(:nb_authorized_nodes, 0)
          |> assign(:current_page, 1)
          |> assign(:transactions, [])

        address when is_binary(address) ->
          nb_authorized_nodes =
            address
            |> TransactionChain.get_last_transaction()
            |> elem(1)
            |> get_in([Access.key(:data), Access.key(:ownerships)])
            |> Enum.at(0)
            |> get_in([Access.key(:authorized_keys)])
            |> Enum.count()

          socket
          |> assign(:tx_count, tx_count)
          |> assign(:nb_pages, total_pages(tx_count))
          |> assign(:nb_authorized_nodes, nb_authorized_nodes)
          |> assign(:current_page, 1)
          |> assign(:transactions, transactions_from_page(1, tx_count))
      end

    {:ok, socket}
  end

  @spec render(assigns :: LiveView.Socket.assigns()) :: LiveView.Rendered.t()
  def render(assigns) do
    View.render(ExplorerView, "node_shared_secrets_chain_index.html", assigns)
  end

  @spec handle_params(_params :: map(), _uri :: binary(), socket :: LiveView.Socket.t()) ::
          {:noreply, LiveView.Socket.t()}
  def handle_params(
        _params = %{"page" => page},
        _uri,
        socket = %{assigns: %{nb_pages: nb_pages, tx_count: tx_count}}
      ) do
    case Integer.parse(page) do
      {number, ""} when number < 1 and number > nb_pages ->
        {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}

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

  @spec handle_event(_event :: binary(), _params :: map(), socket :: LiveView.Socket.t()) ::
          {:noreply, LiveView.Socket.t()}
  def handle_event(_event = "next_page", _params = %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_event(_event = "prev_page", _params = %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  @spec handle_info(
          _msg ::
            {:new_transaction, address :: binary(), :node_shared_secrets, DateTime.t()},
          socket :: LiveView.Socket.t()
        ) ::
          {:noreply, LiveView.Socket.t()}
  def handle_info(
        _msg = {:new_transaction, address, :node_shared_secrets, timestamp},
        socket = %{assigns: %{current_page: current_page, transactions: txs, tx_count: tx_count}}
      ) do
    display_txs = Enum.count(txs)

    updated_socket =
      case current_page do
        1 when display_txs < @display_limit ->
          nb_authorized_nodes = nb_of_authorized_keys(address)

          socket
          |> update(:transactions, &[display_data(address, nb_authorized_nodes, timestamp) | &1])
          |> assign(:tx_count, tx_count + 1)
          |> assign(:nb_authorized_nodes, nb_authorized_nodes)

        1 when display_txs >= @display_limit ->
          nb_authorized_nodes = nb_of_authorized_keys(address)

          socket
          |> assign(:tx_count, tx_count + 1)
          |> assign(:current_page, 1)
          |> assign(:nb_authorized_nodes, nb_authorized_nodes)
          |> assign(:nb_pages, total_pages(tx_count + 1))
          |> assign(:transactions, [display_data(address, nb_authorized_nodes, timestamp)])

        _ ->
          socket
      end

    {:noreply, updated_socket}
  end

  @spec transactions_from_page(current_page :: non_neg_integer(), tx_count :: non_neg_integer()) ::
          list(map())
  def transactions_from_page(current_page, tx_count) do
    nb_drops = tx_count - current_page * @display_limit

    {nb_drops, display_limit} =
      if nb_drops < 0, do: {0, @display_limit + nb_drops}, else: {nb_drops, @display_limit}

    case SharedSecrets.genesis_address(@txn_type) do
      address when is_binary(address) ->
        address
        |> TransactionChain.list_chain_addresses()
        |> Stream.drop(nb_drops)
        |> Stream.take(display_limit)
        |> Stream.map(fn {addr, timestamp} ->
          nb_authorized_nodes = nb_of_authorized_keys(addr)

          display_data(
            addr,
            nb_authorized_nodes,
            DateTime.from_unix(timestamp, :millisecond) |> elem(1)
          )
        end)
        |> Enum.reverse()

      _ ->
        []
    end
  end

  @spec nb_of_authorized_keys(address :: binary()) :: non_neg_integer()
  defp nb_of_authorized_keys(address) do
    TransactionChain.get_transaction(address, data: [:ownerships])
    |> elem(1)
    |> get_in([Access.key(:data), Access.key(:ownerships)])
    |> Enum.at(0)
    |> get_in([Access.key(:authorized_keys)])
    |> Enum.count()
  end

  @spec display_data(
          address :: binary(),
          nb_authorized_nodes :: non_neg_integer(),
          timestamp :: DateTime.t()
        ) ::
          map()
  defp display_data(address, nb_authorized_nodes, timestamp) do
    %{
      address: address,
      type: @txn_type,
      timestamp: timestamp,
      nb_authorized_nodes: nb_authorized_nodes
    }
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
