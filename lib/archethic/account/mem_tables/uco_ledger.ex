defmodule Archethic.Account.MemTables.UCOLedger do
  @moduledoc false

  @ledger_table :archethic_uco_ledger
  @unspent_output_index_table :archethic_uco_unspent_output_index

  alias Archethic.DB

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  use GenServer
  @vsn 1

  require Logger

  @doc """
  Initialize the UCO ledger tables:
  - Main UCO ledger as ETS set ({{to, from}, amount, spent?, timestamp, reward?, protocol_version})
  - UCO Unspent Output Index as ETS bag (to, from)

  The ETS ledger and index caches the unspent UTXO
  Once a UTXO is spent, it is removed from the ETS and written to disk to reduce memory footprint
  """
  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec init(args :: list()) :: {:ok, map()}
  def init(_) do
    Logger.info("Initialize InMemory UCO Ledger...")

    :ets.new(@ledger_table, [:set, :named_table, :public, read_concurrency: true])

    :ets.new(@unspent_output_index_table, [
      :bag,
      :named_table,
      :public,
      read_concurrency: true
    ])

    {:ok,
     %{
       ledger_table: @ledger_table,
       unspent_outputs_index_table: @unspent_output_index_table
     }}
  end

  @doc """
  Add an unspent output to the ledger for the recipient address
  """
  @spec add_unspent_output(
          recipient_address :: binary(),
          utxo :: VersionedUnspentOutput.t()
        ) :: :ok
  def add_unspent_output(
        to,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: from,
            amount: amount,
            reward?: reward?,
            timestamp: %DateTime{} = timestamp
          },
          protocol_version: protocol_version
        }
      )
      when is_binary(to) and is_integer(amount) and amount > 0 do
    spent? =
      case :ets.lookup(@unspent_output_index_table, to) do
        [] ->
          false

        [ledger_key | _] ->
          :ets.lookup_element(@ledger_table, ledger_key, 3)
      end

    true =
      :ets.insert(
        @ledger_table,
        {{to, from}, amount, spent?, timestamp, reward?, protocol_version}
      )

    true = :ets.insert(@unspent_output_index_table, {to, from})

    Logger.info("#{amount} unspent UCO added for #{Base.encode16(to)}",
      transaction_address: Base.encode16(from)
    )

    :ok
  end

  @doc """
  Get the unspent outputs for a given transaction address
  """
  @spec get_unspent_outputs(address :: binary()) :: list(VersionedUnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.reduce([], fn {_, from}, acc ->
      case :ets.lookup(@ledger_table, {address, from}) do
        [{{^address, ^from}, amount, false, timestamp, reward?, protocol_version}] ->
          [
            %VersionedUnspentOutput{
              unspent_output: %UnspentOutput{
                from: from,
                amount: amount,
                type: :UCO,
                reward?: reward?,
                timestamp: timestamp
              },
              protocol_version: protocol_version
            }
            | acc
          ]

        [] ->
          acc
      end
    end)
  end

  @doc """
  Spend all the unspent outputs for the given address.
  """
  @spec spend_all_unspent_outputs(binary()) :: :ok
  def spend_all_unspent_outputs(address) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        :ok

      utxos ->
        {:ok, pid} = DB.start_inputs_writer(:UCO, address)

        Enum.each(utxos, fn {to, from} ->
          [{_, amount, _, timestamp, reward?, protocol_version}] =
            :ets.lookup(@ledger_table, {to, from})

          DB.append_input(pid, %VersionedTransactionInput{
            protocol_version: protocol_version,
            input: %TransactionInput{
              from: from,
              amount: amount,
              spent?: true,
              reward?: reward?,
              timestamp: timestamp,
              type: :UCO
            }
          })

          :ets.delete(@ledger_table, {to, from})
        end)

        :ets.delete(@unspent_output_index_table, address)

        DB.stop_inputs_writer(pid)
    end
  end

  @doc """
  Retrieve the entire inputs for a given address (spent or unspent)
  """
  @spec get_inputs(binary()) :: list(VersionedTransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        DB.get_inputs(:UCO, address)

      inputs ->
        Enum.map(inputs, fn {_, from} ->
          [{_, amount, spent?, timestamp, reward?, protocol_version}] =
            :ets.lookup(@ledger_table, {address, from})

          %VersionedTransactionInput{
            input: %TransactionInput{
              from: from,
              amount: amount,
              spent?: spent?,
              type: :UCO,
              timestamp: timestamp,
              reward?: reward?
            },
            protocol_version: protocol_version
          }
        end)
    end
  end
end
