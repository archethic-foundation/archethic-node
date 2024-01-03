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

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

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
          genesis_address :: binary(),
          input :: VersionedTransactionInput.t()
        ) :: :ok
  def add_chain_input(genesis_address, input = %VersionedTransactionInput{})
      when is_binary(genesis_address) do
    :ets.insert(@table_name, {genesis_address, input})
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
            },
            protocol_version: protocol_version
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
      |> Enum.map(fn %UnspentOutput{
                       from: from,
                       type: type,
                       timestamp: timestamp,
                       amount: amount,
                       encoded_payload: encoded_payload
                     } ->
        %VersionedTransactionInput{
          input: %TransactionInput{
            from: from,
            type: type,
            timestamp: timestamp,
            amount: amount,
            encoded_payload: encoded_payload
          },
          protocol_version: protocol_version
        }
      end)

    # Remove the consumed inputs
    Enum.each(consumed_inputs, fn %UnspentOutput{
                                    from: from,
                                    type: type,
                                    amount: amount,
                                    timestamp: timestamp
                                  } ->
      Logger.debug("Consuming #{Base.encode16(from)} - for #{inspect(genesis_address)}")

      pattern =
        {genesis_address,
         %{
           __struct__: VersionedTransactionInput,
           input: %{
             __struct__: TransactionInput,
             amount: amount,
             from: from,
             timestamp: timestamp,
             type: type
           }
         }}

      :ets.match_delete(@table_name, pattern)
    end)

    Enum.each(updated_inputs, &:ets.insert(@table_name, {genesis_address, &1}))
  end

  @doc """
  Returns the list of all the inputs which have not been consumed for the given chain's address
  """
  @spec get_unspent_inputs(binary()) :: list(VersionedTransactionInput.t())
  def get_unspent_inputs(genesis_address) do
    @table_name
    |> :ets.lookup(genesis_address)
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Insert multiple inputs on a genesis address
  """
  @spec load_inputs(binary(), list(VersionedTransactionInput.t())) :: :ok
  def load_inputs(genesis_address, inputs) do
    objects =
      Enum.map(inputs, fn input ->
        {genesis_address, input}
      end)

    :ets.insert(@table_name, objects)
    :ok
  end
end
