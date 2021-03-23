defmodule Uniris.Account.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias Uniris.Account.MemTables.NFTLedger
  alias Uniris.Account.MemTables.UCOLedger

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.NodeMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  require Logger

  @query_fields [
    :address,
    :previous_public_key,
    validation_stamp: [
      ledger_operations: [:node_movements, :unspent_outputs, :transaction_movements]
    ]
  ]

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    # allocate_genesis_unspent_outputs()

    TransactionChain.list_all(@query_fields)
    |> Stream.each(&load_transaction/1)
    |> Stream.run()

    {:ok, []}
  end

  # defp allocate_genesis_unspent_outputs do
  #   UCOLedger.add_unspent_output(Bootstrap.genesis_unspent_output_address(), %UnspentOutput{
  #     from: Bootstrap.genesis_unspent_output_address(),
  #     amount: Bootstrap.genesis_allocation(),
  #     type: :UCO
  #   })
  # end

  @doc """
  Load the transaction into the memory tables
  """
  @spec load_transaction(Transaction.t()) :: :ok
  def load_transaction(%Transaction{
        address: address,
        type: type,
        timestamp: timestamp,
        previous_public_key: previous_public_key,
        validation_stamp: %ValidationStamp{
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

    Logger.debug("Loaded into in memory account tables",
      transaction: "#{type}@#{Base.encode16(address)}"
    )
  end

  defp set_transaction_movements(address, transaction_movements, timestamp) do
    Enum.each(transaction_movements, fn
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
    |> Enum.filter(&(&1.amount > 0.0))
    |> Enum.each(fn
      unspent_output = %UnspentOutput{type: :UCO} ->
        UCOLedger.add_unspent_output(address, unspent_output, timestamp)

      unspent_output = %UnspentOutput{type: {:NFT, _nft_address}} ->
        NFTLedger.add_unspent_output(address, unspent_output, timestamp)
    end)
  end

  defp set_node_rewards(address, node_movements, timestamp) do
    node_movements
    |> Enum.filter(&(&1.amount > 0.0))
    |> Enum.each(fn %NodeMovement{to: to, amount: amount} ->
      case P2P.get_node_info!(to) do
        # Should only happens during the bootstrap of the network when the first node transaction arrives
        %Node{last_address: nil} ->
          :ok

        %Node{last_address: last_address} ->
          UCOLedger.add_unspent_output(
            last_address,
            %UnspentOutput{amount: amount, from: address, type: :UCO},
            timestamp
          )
      end
    end)
  end
end
