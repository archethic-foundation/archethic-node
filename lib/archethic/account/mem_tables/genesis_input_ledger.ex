defmodule Archethic.Account.MemTables.GenesisInputLedger do
  @moduledoc """
  Represents a memory table for all the inputs associated to a chain
  to give the latest view of unspent inputs based on the consumed inputs
  """

  @table_name :archethic_genesis_input_ledger

  use GenServer
  @vsn Mix.Project.config()[:version]

  require Logger

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput

  @spec start_link(arg :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_args) do
    Logger.info("Initialize InMemory Genesis Input Ledger...")

    :ets.new(@table_name, [:bag, :named_table, :public, read_concurrency: true])

    {:ok, %{table_name: @table_name}}
  end

  @doc """
  Add new input in the genesis ledger
  """
  @spec add_chain_input(
          TransactionMovement.t(),
          tx_address :: binary(),
          tx_timestamp :: DateTime.t(),
          genesis_address :: binary()
        ) :: :ok
  def add_chain_input(
        %TransactionMovement{amount: amount, type: type},
        tx_address,
        tx_timestamp = %DateTime{},
        genesis_address
      )
      when is_binary(tx_address) and is_binary(genesis_address) do
    :ets.insert(
      @table_name,
      {genesis_address,
       %TransactionInput{
         from: tx_address,
         amount: amount,
         type: type,
         timestamp: tx_timestamp
       }}
    )

    :ok
  end

  @doc """
  Update the chain unspent outputs after reduce of the consumed transaction inputs
  """
  @spec update_chain_inputs(Transaction.t(), genesis_address :: binary()) :: :ok
  def update_chain_inputs(
        %Transaction{
          validation_stamp: %ValidationStamp{
            ledger_operations: %LedgerOperations{
              consumed_inputs: consumed_inputs,
              unspent_outputs: unspent_outputs
            }
          }
        },
        genesis_address,
        phase2? \\ false
      )
      when is_binary(genesis_address) do
    # Filter unspent outputs which have been consumed and updated (required in the AEIP21 Phase 1)
    updated_inputs =
      Enum.filter(unspent_outputs, fn %UnspentOutput{type: type} ->
        phase2? or Enum.any?(consumed_inputs, &(&1.type == type))
      end)
      |> Enum.map(fn %UnspentOutput{from: from, type: type, timestamp: timestamp, amount: amount} ->
        %TransactionInput{from: from, type: type, timestamp: timestamp, amount: amount}
      end)

    # Remove the consumed inputs
    Enum.each(consumed_inputs, fn %UnspentOutput{
                                    from: from,
                                    type: type,
                                    amount: amount,
                                    timestamp: timestamp
                                  } ->
      Logger.debug("Consuming #{Base.encode16(from)} - for #{inspect(genesis_address)}")

      :ets.delete_object(
        @table_name,
        {genesis_address,
         %TransactionInput{from: from, type: type, amount: amount, timestamp: timestamp}}
      )
    end)

    Enum.each(updated_inputs, &:ets.insert(@table_name, {genesis_address, &1}))
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec get_unspent_inputs(binary()) :: list(TransactionInput.t())
  def get_unspent_inputs(genesis_address) do
    @table_name
    |> :ets.lookup(genesis_address)
    |> Enum.map(&elem(&1, 1))
  end
end
