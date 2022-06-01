defmodule Archethic.Account.MemTablesLoader do
  @moduledoc false

  use GenServer

  alias Archethic.Account.MemTables.NFTLedger
  alias Archethic.Account.MemTables.UCOLedger

  alias Archethic.Crypto

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  require Logger

  @query_fields [
    :address,
    :type,
    :previous_public_key,
    validation_stamp: [
      :timestamp,
      ledger_operations: [:unspent_outputs, :transaction_movements]
    ]
  ]

  @excluded_types [
    :node,
    :beacon,
    :beacon_summary,
    :oracle,
    :oracle_summary,
    :node_shared_secrets,
    :origin,
    :on_chain_wallet
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
            transaction_movements: transaction_movements
          }
        }
      }) do
    previous_address = Crypto.derive_address(previous_public_key)

    UCOLedger.spend_all_unspent_outputs(previous_address)
    NFTLedger.spend_all_unspent_outputs(previous_address)

    :ok = set_transaction_movements(address, transaction_movements, timestamp)
    :ok = set_unspent_outputs(address, unspent_outputs, timestamp)

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
end
