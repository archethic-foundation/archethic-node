defmodule ArchEthic.P2P.MemTableLoader do
  @moduledoc false

  use GenServer

  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary

  alias ArchEthic.P2P
  alias ArchEthic.P2P.GeoPatch
  alias ArchEthic.P2P.MemTable
  alias ArchEthic.P2P.Node

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Keys

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    nodes_transactions =
      TransactionChain.list_transactions_by_type(:node, [
        :address,
        :type,
        :previous_public_key,
        data: [:content],
        validation_stamp: [:timestamp]
      ])

    beacon_chain_transactions =
      TransactionChain.list_transactions_by_type(
        :beacon_summary,
        [:address, :type, data: [:content], validation_stamp: [:timestamp]]
      )

    node_shared_secret_transactions =
      TransactionChain.list_transactions_by_type(:node_shared_secrets, [
        :address,
        :type,
        data: [:keys],
        validation_stamp: [:timestamp]
      ])

    nodes_transactions
    |> Stream.concat(node_shared_secret_transactions)
    |> Stream.concat(beacon_chain_transactions)
    |> Enum.sort_by(& &1.validation_stamp.timestamp, {:asc, DateTime})
    |> Enum.each(&load_transaction/1)

    {:ok, %{}}
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

    {:ok, ip, port, transport, reward_address, _} = Node.decode_transaction_content(content)

    node = %Node{
      ip: ip,
      port: port,
      first_public_key: first_public_key,
      last_public_key: previous_public_key,
      geo_patch: GeoPatch.from_ip(ip),
      transport: transport,
      last_address: address,
      reward_address: reward_address
    }

    if first_node_change?(first_public_key, previous_public_key) do
      node
      |> Node.enroll(timestamp)
      |> MemTable.add_node()
    else
      MemTable.add_node(node)
    end

    Logger.info("Node loaded into in memory p2p tables", node: Base.encode16(first_public_key))
  end

  def load_transaction(%Transaction{
        address: address,
        type: :node_shared_secrets,
        data: %TransactionData{keys: keys},
        validation_stamp: %ValidationStamp{
          timestamp: timestamp
        }
      }) do
    Logger.info("Loading transaction into P2P mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :node_shared_secrets
    )

    new_authorized_keys = Keys.list_authorized_keys(keys)
    previous_authorized_keys = P2P.authorized_nodes() |> Enum.map(& &1.last_public_key)

    unauthorized_keys = previous_authorized_keys -- new_authorized_keys

    Enum.each(unauthorized_keys, &MemTable.unauthorize_node/1)

    keys
    |> Keys.list_authorized_keys()
    |> Enum.map(&MemTable.get_first_node_key/1)
    |> Enum.each(&MemTable.authorize_node(&1, SharedSecrets.next_application_date(timestamp)))
  end

  def load_transaction(%Transaction{
        address: address,
        type: :beacon_summary,
        data: %TransactionData{content: content}
      }) do
    Logger.info("Loading transaction into P2P mem table",
      transaction_address: Base.encode16(address),
      transaction_type: :beacon_summary
    )

    {summary = %BeaconSummary{
       end_of_node_synchronizations: end_of_node_sync
     }, _} = BeaconSummary.deserialize(content)

    Enum.each(end_of_node_sync, &MemTable.set_node_available(&1.public_key))

    summary
    |> BeaconSummary.get_node_availabilities()
    |> Enum.each(fn {%Node{first_public_key: key}, available?} ->
      if available? do
        MemTable.set_node_available(key)
      else
        MemTable.set_node_unavailable(key)
      end
    end)
  end

  def load_transaction(_), do: :ok

  defp first_node_change?(first_key, previous_key) when first_key == previous_key, do: true
  defp first_node_change?(_, _), do: false
end
