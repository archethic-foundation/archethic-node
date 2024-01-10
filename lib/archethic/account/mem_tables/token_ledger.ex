defmodule Archethic.Account.MemTables.TokenLedger do
  @moduledoc false

  @ledger_table :archethic_token_ledger
  @unspent_output_index_table :archethic_token_unspent_output_index

  alias Archethic.DB

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput

  use GenServer
  @vsn 1

  require Logger

  @doc """
  Initialize the Token ledger tables:
  - Main Token ledger as ETS set ({to, from, token_address, token_id}, amount, spent?, timestamp, protocol_version)
  - Token Unspent Output Index as ETS bag (to, from, token_address, token_id)

  The ETS ledger and index caches the unspent UTXO
  Once a UTXO is spent, it is removed from the ETS and written to disk to reduce memory footprint
  """
  @spec start_link(args :: list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec init(args :: list()) :: {:ok, map()}
  def init(_) do
    Logger.info("Initialize InMemory Token Ledger...")

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
        to_address,
        %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: from_address,
            amount: amount,
            type: {:token, token_address, token_id},
            timestamp: %DateTime{} = timestamp
          },
          protocol_version: protocol_version
        }
      )
      when is_binary(to_address) and is_binary(from_address) and is_integer(amount) and amount > 0 and
             is_binary(token_address) and is_integer(token_id) and token_id >= 0 do
    spent? =
      case :ets.lookup(@unspent_output_index_table, to_address) do
        [] ->
          false

        [ledger_key | _] ->
          :ets.lookup_element(@ledger_table, ledger_key, 3)
      end

    true =
      :ets.insert(
        @ledger_table,
        {{to_address, from_address, token_address, token_id}, amount, spent?, timestamp,
         protocol_version}
      )

    true =
      :ets.insert(
        @unspent_output_index_table,
        {to_address, from_address, token_address, token_id}
      )

    Logger.info(
      "#{amount} unspent Token (#{Base.encode16(token_address)}) added for #{Base.encode16(to_address)}",
      transaction_address: Base.encode16(from_address)
    )

    :ok
  end

  @doc """
  Get the unspent outputs for a given transaction address
  """
  @spec get_unspent_outputs(binary()) :: list(VersionedUnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    @unspent_output_index_table
    |> :ets.lookup(address)
    |> Enum.reduce([], fn {_, from, token_address, token_id}, acc ->
      case :ets.lookup(@ledger_table, {address, from, token_address, token_id}) do
        [{_, amount, false, timestamp, protocol_version}] ->
          [
            %VersionedUnspentOutput{
              unspent_output: %UnspentOutput{
                from: from,
                amount: amount,
                type: {:token, token_address, token_id},
                timestamp: timestamp
              },
              protocol_version: protocol_version
            }
            | acc
          ]

        _ ->
          acc
      end
    end)
  end

  @doc """
  Spend all the unspent outputs for the given address
  """
  @spec spend_all_unspent_outputs(binary()) :: :ok
  def spend_all_unspent_outputs(address) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        :ok

      utxos ->
        {:ok, pid} = DB.start_inputs_writer(:token, address)

        Enum.each(utxos, fn {to, from, token_address, token_id} ->
          [{_, amount, _, timestamp, protocol_version}] =
            :ets.lookup(@ledger_table, {to, from, token_address, token_id})

          DB.append_input(pid, %VersionedTransactionInput{
            protocol_version: protocol_version,
            input: %TransactionInput{
              from: from,
              amount: amount,
              spent?: true,
              timestamp: timestamp,
              type: {:token, token_address, token_id}
            }
          })

          :ets.delete(@ledger_table, {address, from, token_address, token_id})
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
        DB.get_inputs(:token, address)

      inputs ->
        Enum.map(inputs, fn {_, from, token_address, token_id} ->
          [{_, amount, spent?, timestamp, protocol_version}] =
            :ets.lookup(@ledger_table, {address, from, token_address, token_id})

          %VersionedTransactionInput{
            input: %TransactionInput{
              from: from,
              amount: amount,
              type: {:token, token_address, token_id},
              spent?: spent?,
              timestamp: timestamp
            },
            protocol_version: protocol_version
          }
        end)
    end
  end
end
