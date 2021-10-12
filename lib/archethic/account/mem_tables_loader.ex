defmodule ArchEthic.Account.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias ArchEthic.Account.MemTables.NFTLedger
  alias ArchEthic.Account.MemTables.UCOLedger

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  require Logger

  @query_fields [
    :address,
    :type,
    :previous_public_key,
    validation_stamp: [
      :timestamp,
      ledger_operations: [:node_movements, :unspent_outputs, :transaction_movements]
    ]
  ]

  @excluded_types [
    :node,
    :beacon,
    :beacon_summary,
    :oracle,
    :oracle_summary,
    :node_shared_secrets,
    :origin_shared_secrets
  ]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    TransactionChain.list_all(@query_fields)
    |> Stream.reject(&(&1.type in @excluded_types))
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Load the transaction into the memory tables
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        address: address,
        type: type,
        previous_public_key: previous_public_key,
        validation_stamp: %ValidationStamp{
          timestamp: timestamp,
          ledger_operations: %LedgerOperations{
            unspent_outputs: unspent_outputs,
            node_movements: node_movements,
            transaction_movements: transaction_movements
          }
        }
      }) do
    previous_address = Crypto.hash(previous_public_key)

    UCOLedger.spend_all_unspent_outputs(previous_address)
    NFTLedger.spend_all_unspent_outputs(previous_address)

    :ok = set_transaction_movements(address, transaction_movements, timestamp)
    :ok = set_unspent_outputs(address, unspent_outputs, timestamp)
    :ok = set_node_rewards(address, node_movements, timestamp)

    Logger.info("Loaded into in memory account tables",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )
  end

  defp set_transaction_movements(address, transaction_movements, timestamp) do
    transaction_movements
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.reject(&(&1.to == LedgerOperations.burning_address()))
    |> Enum.each(fn
      %TransactionMovement{to: to, amount: amount, type: :UCO} ->
        UCOLedger.add_unspent_output(
          to,
          %UnspentOutput{amount: amount, from: address, type: :UCO},
          timestamp
        )

      %TransactionMovement{to: to, amount: amount, type: {:NFT, nft_address}} ->
        NFTLedger.add_unspent_output(
          to,
          %UnspentOutput{
            amount: amount,
            from: address,
            type: {:NFT, nft_address}
          },
          timestamp
        )
    end)
  end

  defp set_unspent_outputs(address, unspent_outputs, timestamp) do
    unspent_outputs
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.each(fn
      unspent_output = %UnspentOutput{type: :UCO} ->
        UCOLedger.add_unspent_output(address, unspent_output, timestamp)

      unspent_output = %UnspentOutput{type: {:NFT, _nft_address}} ->
        NFTLedger.add_unspent_output(address, unspent_output, timestamp)
    end)
  end

  defp set_node_rewards(address, node_movements, timestamp) do
    node_movements
    |> Enum.filter(&(&1.amount > 0))
    |> Enum.each(fn %NodeMovement{to: to, amount: amount} ->
      %Node{reward_address: reward_address} = P2P.get_node_info!(to)

      UCOLedger.add_unspent_output(
        reward_address,
        %UnspentOutput{amount: amount, from: address, type: :UCO, reward?: true},
        timestamp
      )
    end)
  end
end
