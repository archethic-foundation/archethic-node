defmodule Archethic.Account.MemTables.StateLedger do
  @moduledoc """
  A bit different than the token & uco ledgers.
  This one can contain only 1 value by chain (instead of N values per transaction)
  """

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  use GenServer
  @vsn 2

  require Logger

  @ledger_table :archethic_state_ledger

  @doc """
  Starts the GenServer that owns the ETS table
  """
  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get the state of given contract or nil
  """
  # @spec get_unspent_output(Crypto.prepended_hash()) :: nil | VersionedUnspentOutput.t()
  def get_unspent_output(address) when is_binary(address) do
    case :ets.lookup(@ledger_table, address) do
      [] ->
        nil

      [{^address, encoded_payload, timestamp, protocol_version}] ->
        %VersionedUnspentOutput{
          protocol_version: protocol_version,
          unspent_output: %UnspentOutput{
            type: :state,
            encoded_payload: encoded_payload,
            from: address,
            timestamp: timestamp
          }
        }
    end
  end

  @doc """
  Set the state for given contract's address
  """
  @spec add_unspent_output(Crypto.prepended_hash(), VersionedUnspentOutput.t()) :: :ok
  def add_unspent_output(address, %VersionedUnspentOutput{
        unspent_output: %UnspentOutput{
          type: :state,
          encoded_payload: encoded_payload,
          timestamp: timestamp
        },
        protocol_version: protocol_version
      })
      when is_binary(address) do
    true = Crypto.valid_address?(address)

    true =
      :ets.insert(
        @ledger_table,
        {address, encoded_payload, timestamp, protocol_version}
      )

    :ok
  end

  @doc """
  Spend the state (deletes it)
  """
  @spec spend_all_unspent_outputs(Crypto.prepended_hash()) :: :ok
  def spend_all_unspent_outputs(address) when is_binary(address) do
    :ets.delete(@ledger_table, address)
    :ok
  end

  ###############
  # CALLBACKS
  ###############
  @spec init(args :: list()) :: {:ok, :no_state}
  def init([]) do
    Logger.info("Initialize InMemory State Ledger...")
    :ets.new(@ledger_table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, :no_state}
  end

  # add timestamp in the ETS table
  def code_change(1, state, _extra) do
    elements =
      :ets.tab2list(@ledger_table)
      |> Enum.map(fn {address, encoded_payload, protocol_version} ->
        {address, encoded_payload, nil, protocol_version}
      end)

    # since it's a set it will override them
    :ets.insert(@ledger_table, elements)

    {:ok, state}
  end

  def code_change(_version, state, _extra), do: {:ok, state}
end
