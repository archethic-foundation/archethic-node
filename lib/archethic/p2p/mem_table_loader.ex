defmodule ArchEthic.P2P.MemTableLoader do
  @moduledoc false

  use GenServer

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Client
  alias ArchEthic.P2P.GeoPatch
  alias ArchEthic.P2P.MemTable
  alias ArchEthic.P2P.Node

  alias ArchEthic.SharedSecrets

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ownership

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

    node_shared_secret_transactions =
      DB.list_transactions_by_type(:node_shared_secrets, [
        :address,
        :type,
        data: [:ownerships],
        validation_stamp: [:timestamp]
      ])
      |> Enum.at(0)

    nodes_transactions
    |> Stream.concat([node_shared_secret_transactions])
    |> Stream.filter(& &1)
    |> Enum.sort_by(& &1.validation_stamp.timestamp, {:asc, DateTime})
    |> Enum.each(&load_transaction/1)

    Enum.each(DB.get_last_p2p_summaries(), &load_p2p_summary/1)

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

    {:ok, ip, port, http_port, transport, reward_address, _} =
      Node.decode_transaction_content(content)

    node = %Node{
      ip: ip,
      port: port,
      http_port: http_port,
      first_public_key: first_public_key,
      last_public_key: previous_public_key,
      geo_patch: GeoPatch.from_ip(ip),
      transport: transport,
      last_address: address,
      reward_address: reward_address
    }

    IO.inspect(node,
      label: "<---------- [node] ---------->",
      limit: :infinity,
      printable_limit: :infinity
    )

    if first_node_change?(first_public_key, previous_public_key) do
      node
      |> Node.enroll(timestamp)
      |> MemTable.add_node()
    else
      MemTable.add_node(node)
    end

    Logger.info("Node loaded into in memory p2p tables", node: Base.encode16(first_public_key))

    if first_public_key != Crypto.first_node_public_key() do
      case Client.new_connection(ip, port, transport, first_public_key) do
        {:ok, _} ->
          :ok

        {:error, {:already_started, _}} ->
          :ok
      end
    else
      :ok
    end
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
    previous_authorized_keys = P2P.authorized_nodes() |> Enum.map(& &1.last_public_key)

    unauthorized_keys = previous_authorized_keys -- new_authorized_keys

    Enum.each(unauthorized_keys, &MemTable.unauthorize_node/1)

    new_authorized_keys
    |> Enum.map(&MemTable.get_first_node_key/1)
    |> Enum.each(&MemTable.authorize_node(&1, SharedSecrets.next_application_date(timestamp)))
  end

  def load_transaction(_), do: :ok

  defp first_node_change?(first_key, previous_key) when first_key == previous_key, do: true
  defp first_node_change?(_, _), do: false

  defp load_p2p_summary({node_public_key, {available?, avg_availability}}) do
    if available? do
      MemTable.set_node_available(node_public_key)
    end

    MemTable.update_node_average_availability(node_public_key, avg_availability)
  end
end
