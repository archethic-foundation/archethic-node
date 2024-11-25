defmodule ArchethicWeb.Explorer.NodeSharedSecretsChainLive do
  @moduledoc false

  use ArchethicWeb.Explorer, :live_view

  alias Archethic.Crypto
  alias Archethic.OracleChain
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.PubSub
  alias Archethic.SharedSecrets
  alias ArchethicWeb.WebUtils
  alias ArchethicWeb.Explorer.Components.TransactionsList
  alias Phoenix.LiveView

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
      case SharedSecrets.genesis_address(@txn_type) do
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
            |> TransactionChain.get_last_address()
            |> elem(0)
            |> nb_of_authorized_keys()

          socket
          |> assign(:tx_count, tx_count)
          |> assign(:nb_pages, WebUtils.total_pages(tx_count))
          |> assign(:nb_authorized_nodes, nb_authorized_nodes)
          |> assign(:current_page, 1)
          |> assign(:transactions, transactions_from_page(1, tx_count))
          |> assign(:uco_price_now, DateTime.utc_now() |> OracleChain.get_uco_price())
      end

    {:ok, socket}
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

      {number, ""} when number >= 1 and number <= nb_pages ->
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
  def handle_event("goto", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @spec handle_info(
          _msg ::
            {:new_transaction, address :: binary(), :node_shared_secrets, DateTime.t()},
          socket :: LiveView.Socket.t()
        ) ::
          {:noreply, LiveView.Socket.t()}
  def handle_info(
        _msg = {:new_transaction, address, :node_shared_secrets, timestamp},
        socket = %{assigns: %{current_page: current_page, tx_count: tx_count}}
      ) do
    updated_socket =
      case current_page do
        1 ->
          nb_auth_nodes = nb_of_authorized_keys(address)

          socket
          |> update(
            :transactions,
            fn tx_list ->
              [
                display_data(
                  SharedSecrets.genesis_address(@txn_type),
                  address,
                  nb_auth_nodes,
                  timestamp
                )
                | tx_list
              ]
              |> Enum.take(@display_limit)
            end
          )
          |> assign(:tx_count, tx_count + 1)
          |> assign(:nb_authorized_nodes, nb_auth_nodes)
          |> assign(:current_page, 1)
          |> assign(:nb_pages, WebUtils.total_pages(tx_count + 1))

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
      genesis_address when is_binary(genesis_address) ->
        genesis_address
        |> TransactionChain.list_chain_addresses()
        |> Stream.drop(nb_drops)
        |> Stream.take(display_limit)
        |> Stream.map(fn {addr, timestamp} ->
          nb_authorized_nodes = nb_of_authorized_keys(addr)

          display_data(
            genesis_address,
            addr,
            nb_authorized_nodes,
            timestamp
          )
        end)
        |> Enum.reverse()

      _ ->
        []
    end
  end

  @spec nb_of_authorized_keys(address :: binary()) :: non_neg_integer()
  defp nb_of_authorized_keys(address) do
    with {:ok, %Transaction{data: %TransactionData{ownerships: ownerships}}} <-
           TransactionChain.get_transaction(address, data: [:ownerships]),
         %Ownership{authorized_keys: authorized_keys} <- Enum.at(ownerships, 0) do
      Enum.count(authorized_keys)
    else
      _ -> 1
    end
  end

  @spec display_data(
          genesis_address :: Crypto.prepended_hash(),
          address :: Crypto.prepended_hash(),
          nb_authorized_nodes :: non_neg_integer(),
          timestamp :: DateTime.t()
        ) ::
          map()
  defp display_data(genesis_address, address, nb_authorized_nodes, timestamp) do
    %{
      genesis_address: genesis_address,
      address: address,
      type: @txn_type,
      timestamp: timestamp,
      nb_authorized_nodes: nb_authorized_nodes
    }
  end
end
