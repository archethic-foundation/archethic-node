defmodule Archethic.Account.MemTables.TokenLedger do
  @moduledoc false
  alias Archethic.{DB, TransactionChain}
  alias TransactionChain.{Transaction, TransactionInput, VersionedTransactionInput}
  alias Transaction.ValidationStamp.LedgerOperations.{UnspentOutput, VersionedUnspentOutput}

  @ledger_table :archethic_token_ledger
  @unspent_output_index_table :archethic_token_unspent_output_index
  @threshold Application.compile_env!(:archethic, [__MODULE__, :ets_threshold])

  use GenServer
  @vsn Mix.Project.config()[:version]

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
    :ets.new(@unspent_output_index_table, [:bag, :named_table, :public, read_concurrency: true])

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
          utxo :: VersionedUnspentOutput.t(),
          from_init? :: boolean()
        ) :: :ok
  def add_unspent_output(
        to_address,
        input = %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: from_address,
            amount: amount,
            type: {:token, token_address, token_id}
          }
        },
        from_init? \\ false
      )
      when is_binary(to_address) and is_binary(from_address) and is_integer(amount) and amount > 0 and
             is_binary(token_address) and is_integer(token_id) and token_id >= 0 do
    case :ets.lookup(@unspent_output_index_table, to_address) do
      [{^to_address, true}] ->
        append_input_to_db(to_address, input, from_init?)

      _ ->
        # any [] or inputs
        ingest(to_address, input, from_init?)
    end

    Logger.info(
      "#{amount} unspent Token (#{Base.encode16(token_address)}) added for #{Base.encode16(to_address)}",
      transaction_address: Base.encode16(from_address)
    )

    :ok
  end

  defp ingest(
         to_address,
         %VersionedUnspentOutput{
           unspent_output: %UnspentOutput{
             from: from_address,
             amount: amount,
             type: {:token, token_address, token_id},
             timestamp: %DateTime{} = timestamp
           },
           protocol_version: protocol_version
         },
         from_init?
       ) do
    true =
      @ledger_table
      |> :ets.insert(
        {{to_address, from_address, token_address, token_id}, amount, false, timestamp,
         protocol_version}
      )

    true =
      @unspent_output_index_table
      |> :ets.insert({to_address, from_address, token_address, token_id})

    inputs = :ets.lookup(@unspent_output_index_table, to_address)

    if length(inputs) > @threshold do
      # flush to the db
      write_to_db(to_address, inputs, from_init?)
      # flag to know inputs were flushed to the db regardles of the flag
      :ets.insert(@unspent_output_index_table, {to_address, _in_db = true})
    end
  end

  defp append_input_to_db(_, _, true), do: :ok

  defp append_input_to_db(
         address,
         %VersionedUnspentOutput{
           unspent_output: %UnspentOutput{
             from: from_address,
             amount: amount,
             type: {:token, token_address, token_id},
             timestamp: %DateTime{} = timestamp
           },
           protocol_version: protocol_version
         },
         false
       ) do
    {:ok, pid} = DB.start_inputs_writer(:token, address)

    DB.append_input(pid, %VersionedTransactionInput{
      protocol_version: protocol_version,
      input: %TransactionInput{
        from: from_address,
        amount: amount,
        spent?: true,
        timestamp: timestamp,
        type: {:token, token_address, token_id}
      }
    })

    DB.stop_inputs_writer(pid)
  end

  @doc """
  Get the unspent outputs for a given transaction address
  """
  @spec get_unspent_outputs(binary()) :: list(VersionedUnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        # if above threshold ,was written to db and ets was cleared
        []

      [{^address, true}] ->
        # exists in db file, return as spent false
        :token
        |> DB.get_inputs(address)
        |> Enum.reduce([], fn
          %VersionedTransactionInput{
            input: %TransactionInput{
              from: from,
              amount: amount,
              spent?: _,
              type: {:token, token_address, token_id},
              timestamp: timestamp,
              reward?: reward?
            },
            protocol_version: protocol_version
          },
          acc ->
            [
              %VersionedUnspentOutput{
                unspent_output: %UnspentOutput{
                  from: from,
                  amount: amount,
                  type: {:token, token_address, token_id},
                  reward?: reward?,
                  timestamp: timestamp
                },
                protocol_version: protocol_version
              }
              | acc
            ]

          _, acc ->
            acc
        end)

      inputs ->
        # did not reach threshold
        build_utxos(address, inputs)
    end
  end

  defp build_utxos(address, inputs) do
    inputs
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
  Retrieve the entire inputs for a given address (spent or unspent)
  """
  @spec get_inputs(binary()) :: list(VersionedTransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        :token
        |> DB.get_inputs(address)

      [{^address, true}] ->
        :token
        |> DB.get_inputs(address)
        |> Enum.map(
          &%VersionedTransactionInput{&1 | input: %TransactionInput{&1.input | spent?: false}}
        )

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

  @doc """
  Spend all the unspent outputs for the given address
  """
  @spec spend_all_unspent_outputs(address :: binary(), from_init? :: boolean()) :: :ok
  def spend_all_unspent_outputs(address, from_init? \\ false) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        :ok

      [{^address, true}] ->
        :ets.delete(@unspent_output_index_table, address)
        :ok

      utxos ->
        write_to_db(address, utxos, from_init?)
    end
  end

  defp write_to_db(address, inputs, false) do
    {:ok, pid} = DB.start_inputs_writer(:token, address)

    Enum.each(inputs, fn {to, from, token_address, token_id} ->
      [{_, amount, _spent, timestamp, protocol_version}] =
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

  defp write_to_db(address, inputs, true) do
    Enum.each(inputs, fn {_to, from, token_address, token_id} ->
      :ets.delete(@ledger_table, {address, from, token_address, token_id})
    end)

    :ets.delete(@unspent_output_index_table, address)
  end
end
