defmodule ArchethicWeb.OriginChainLive do
  @moduledoc false
  use ArchethicWeb, :live_view

  alias Archethic.{
    TransactionChain,
    PubSub,
    SharedSecrets,
    Utils
  }

  alias ArchethicWeb.{ExplorerView}
  alias Phoenix.{LiveView, View}

  @display_limit 10
  @txn_type :origin

  @spec mount(_parameters :: map(), _session :: map(), socket :: LiveView.Socket.t()) ::
          {:ok, LiveView.Socket.t()}
  def mount(_parameters, _session, socket) do
    if connected?(socket) do
      PubSub.register_to_new_transaction_by_type(@txn_type)
    end

    tx_count = TransactionChain.count_transactions_by_type(@txn_type)

    socket =
      socket
      |> assign(:tx_count, tx_count)
      |> assign(:nb_pages, total_pages(tx_count))
      |> assign(:current_page, 1)
      |> assign(:transactions, transactions_from_page(1, tx_count))

    {:ok, socket}
  end

  @spec render(assigns :: LiveView.Socket.assigns()) :: LiveView.Rendered.t()
  def render(assigns) do
    View.render(ExplorerView, "origin_chain_index.html", assigns)
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
  def handle_event(_event = "prev_page", _params = %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_event(_event = "next_page", _params = %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  @spec handle_info(_msg :: any(), socket :: LiveView.Socket.t()) ::
          {:noreply, LiveView.Socket.t()}
  def handle_info(
        _msg = {:new_transaction, address, :origin, _timestamp},
        socket = %{
          assigns: %{
            current_page: current_page,
            transactions: tranasction_list,
            tx_count: total_tx_count
          }
        }
      ) do
    display_txs = Enum.count(tranasction_list)

    updated_socket =
      case current_page do
        1 when display_txs < @display_limit ->
          {family_of_origin, timestamp} = tx_details(address)

          socket
          |> update(
            :transactions,
            &[
              %{
                address: address,
                type: @txn_type,
                timestamp: timestamp,
                family_of_origin: family_of_origin
              }
              | &1
            ]
          )
          |> assign(:tx_count, total_tx_count + 1)

        1 when display_txs >= @display_limit ->
          {family_of_origin, timestamp} = tx_details(address)

          socket
          |> assign(:tx_count, total_tx_count + 1)
          |> assign(:current_page, 1)
          |> assign(:nb_pages, total_pages(total_tx_count + 1))
          |> assign(:transactions, [
            %{
              address: address,
              type: @txn_type,
              timestamp: timestamp,
              family_of_origin: family_of_origin
            }
          ])

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

    TransactionChain.list_addresses_by_type(:origin)
    |> Stream.drop(nb_drops)
    |> Stream.take(display_limit)
    |> Stream.map(fn
      nil ->
        nil

      address ->
        {family_of_origin, timestamp} = tx_details(address)

        %{
          address: address,
          type: @txn_type,
          timestamp: timestamp,
          family_of_origin: family_of_origin
        }
    end)
    |> Enum.reverse()
  end

  defp tx_details(address) do
    tx =
      TransactionChain.get_transaction(address, data: [:content], validation_stamp: [:timestamp])
      |> elem(1)

    family_of_origin =
      tx
      |> get_in([Access.key(:data), Access.key(:content)])
      |> Utils.deserialize_public_key()
      |> elem(0)
      |> SharedSecrets.origin_family_from_public_key()

    timestamp =
      tx
      |> get_in([Access.key(:validation_stamp), Access.key(:timestamp)])

    {family_of_origin, timestamp}
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
