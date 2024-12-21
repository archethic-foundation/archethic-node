defmodule Archethic.P2P.MemTableLoader do
  @moduledoc false

  use GenServer
  @vsn 1

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.P2P.GeoPatch
  alias Archethic.P2P.MemTable
  alias Archethic.P2P.Node

  alias Archethic.SelfRepair

  alias Archethic.SharedSecrets

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ownership

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    nodes_transactions =
      DB.list_transactions_by_type(:node, [
        :address,
        :type,
        :previous_public_key,
        data: [:content],
        validation_stamp: [:timestamp]
      ])

    node_shared_secret_txs =
      DB.list_transactions_by_type(:node_shared_secrets, [
        :address,
        :type,
        data: [:ownerships],
        validation_stamp: [:timestamp]
      ])

    nodes_transactions
    |> Stream.concat(node_shared_secret_txs)
    |> Stream.filter(& &1)
    |> Enum.sort_by(& &1.validation_stamp.timestamp, {:asc, DateTime})
    |> Enum.each(&load_transaction/1)

    SelfRepair.last_sync_date() |> load_p2p_view()

    {:ok, %{}}
  end

  @spec load_p2p_view(DateTime.t() | nil) :: :ok
  def load_p2p_view(nil), do: :ok

  def load_p2p_view(last_sync_date) do
    p2p_summaries = DB.get_last_p2p_summaries()
    previously_available = Enum.filter(p2p_summaries, &match?({_, true, _, _, _}, &1))

    node_key = Crypto.first_node_public_key()

    case previously_available do
      # Ensure the only single node is globally available after a delayed bootstrap
      [{^node_key, _, avg_availability, availability_update, network_patch}] ->
        MemTable.set_node_synced(node_key)
        MemTable.set_node_available(node_key, availability_update)
        MemTable.update_node_average_availability(node_key, avg_availability)
        MemTable.update_node_network_patch(node_key, network_patch)

      [] ->
        MemTable.set_node_synced(node_key)
        MemTable.set_node_available(node_key, last_sync_date)
        MemTable.update_node_average_availability(node_key, 1.0)

      _ ->
        Enum.each(p2p_summaries, &load_p2p_summary/1)
    end
  end

  @doc """
  Load the transaction and update the P2P view
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        address: address,
        type: :node,
        previous_public_key: previous_public_key,
        data: %TransactionData{content: content},
        validation_stamp: %ValidationStamp{
          timestamp: timestamp
        }
      }) do
    Logger.info("Loading transaction into P2P mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :node
    )

    first_public_key = TransactionChain.get_first_public_key(previous_public_key)

    {:ok, ip, port, http_port, transport, reward_address, origin_public_key, _certificate,
     mining_public_key, geo_patch} = Node.decode_transaction_content(content)

    geo_patch = if geo_patch == nil, do: GeoPatch.from_ip(ip), else: geo_patch

    if first_node_change?(first_public_key, previous_public_key) do
      node = %Node{
        ip: ip,
        port: port,
        http_port: http_port,
        first_public_key: first_public_key,
        last_public_key: previous_public_key,
        geo_patch: geo_patch,
        transport: transport,
        last_address: address,
        reward_address: reward_address,
        origin_public_key: origin_public_key,
        last_update_date: timestamp,
        mining_public_key: mining_public_key
      }

      node
      |> Node.enroll(timestamp)
      |> MemTable.add_node()
    else
      {:ok, node} = MemTable.get_node(first_public_key)

      MemTable.add_node(%{
        node
        | ip: ip,
          port: port,
          http_port: http_port,
          last_public_key: previous_public_key,
          geo_patch: geo_patch,
          transport: transport,
          last_address: address,
          reward_address: reward_address,
          origin_public_key: origin_public_key,
          last_update_date: timestamp,
          mining_public_key: mining_public_key
      })
    end

    Logger.info("Node loaded into in memory p2p tables", node: Base.encode16(first_public_key))
  end

  def load_transaction(%Transaction{
        address: address,
        type: :node_shared_secrets,
        data: %TransactionData{ownerships: [ownership = %Ownership{}]},
        validation_stamp: %ValidationStamp{
          timestamp: timestamp
        }
      }) do
    Logger.info("Loading transaction into P2P mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :node_shared_secrets
    )

    new_authorized_keys = Ownership.list_authorized_public_keys(ownership)
    previous_authorized_keys = MemTable.list_authorized_public_keys()

    unauthorized_keys = previous_authorized_keys -- new_authorized_keys

    Enum.each(unauthorized_keys, &MemTable.unauthorize_node/1)

    new_authorized_keys
    |> Enum.map(&MemTable.get_first_node_key/1)
    |> Enum.each(&MemTable.authorize_node(&1, SharedSecrets.next_application_date(timestamp)))
  end

  def load_transaction(_), do: :ok

  defp first_node_change?(first_key, previous_key) when first_key == previous_key, do: true
  defp first_node_change?(_, _), do: false

  defp load_p2p_summary(
         {node_public_key, available?, avg_availability, availability_update, network_patch}
       ) do
    MemTable.update_node_average_availability(node_public_key, avg_availability)
    MemTable.update_node_network_patch(node_public_key, network_patch)

    if available? do
      MemTable.set_node_synced(node_public_key)
      MemTable.set_node_available(node_public_key, availability_update)
    else
      MemTable.set_node_unavailable(node_public_key, availability_update)
    end
  end
end
