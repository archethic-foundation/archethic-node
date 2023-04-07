defmodule Archethic.Account.MemTables.UCOLedger do
  @moduledoc """
  In-memory UCO Ledger: When inputs are within threshold.
      - add_unspent_output handled in ETS
      - get_unspent_outputs handled in ETS
      - get_inputs handled in ETS
      - spend_all_unspent_outputs , flush to DB file
      (and inputs to be used as utxo for the next tx is handled by the new tx
      which is dealt in load transaciton memtables laoder. And now it is the issue of new address and its new file )
  In-DB UCO Ledger: When inputs are above threshold.
      - add_unspent_output handled by flushing all inputs to DB file with spent true
      - get_unspent_outputs handled by loading all inputs from DB file and returns as not spent, as utxo
      which is handled by manually confirming whether they are utxo or spent,
      - get_inputs, handled by read from DB file . and spent flag doesnt matter
      - spend_all_unspent_outputs , we do nothing as we already flushed everything to DB file as spent
      (and inputs to be used as utxo for the next tx is handled by the new tx and are remove the flag its in db.
  """
  alias Archethic.{DB, TransactionChain}
  alias TransactionChain.{Transaction, TransactionInput, VersionedTransactionInput}
  alias Transaction.ValidationStamp.LedgerOperations.{UnspentOutput, VersionedUnspentOutput}

  @ledger_table Application.compile_env!(:archethic, [__MODULE__, :ledger_table])
  @unspent_output_index_table Application.compile_env!(:archethic, [__MODULE__, :utxo_table])
  # configurable at runtime
  @threshold Application.compile_env!(:archethic, [__MODULE__, :ets_threshold])

  use GenServer
  @vsn Mix.Project.config()[:version]

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

    :ets.new(@unspent_output_index_table, [:bag, :named_table, :public, read_concurrency: true])

    {:ok,
     %{ledger_table: @ledger_table, unspent_outputs_index_table: @unspent_output_index_table}}
  end

  @doc """
  Add an unspent output to the ledger for the recipient address
  """
  @spec add_unspent_output(
          to_address :: binary(),
          utxo :: VersionedUnspentOutput.t(),
          from_init? :: boolean()
        ) :: :ok
  def add_unspent_output(
        to_address,
        input = %VersionedUnspentOutput{
          unspent_output: %UnspentOutput{
            from: from,
            amount: amount,
            reward?: reward?,
            timestamp: %DateTime{} = timestamp
          },
          protocol_version: protocol_version
        },
        from_init?
      )
      when is_binary(to_address) and is_integer(amount) and amount > 0 do
    case :ets.lookup(@unspent_output_index_table, to_address) do
      [{^to_address, true}] ->
        append_input_to_db(to_address, input, from_init?)

      inputs ->
        true =
          :ets.insert(
            @ledger_table,
            {{to_address, from}, amount, false, timestamp, reward?, protocol_version}
          )

        true = :ets.insert(@unspent_output_index_table, {to_address, from})

        if length(inputs) + 1 > @threshold do
          # flush to db # write_to_db(to)
          write_to_db(to_address, inputs, from_init?)
          :ets.insert(@unspent_output_index_table, {to_address, _in_db = true})
        end
    end

    Logger.info("#{amount} unspent UCO added for #{Base.encode16(to_address)}",
      transaction_address: Base.encode16(from)
    )

    :ok
  end

  defp append_input_to_db(_, _, true), do: :ok

  defp append_input_to_db(
         address,
         %VersionedUnspentOutput{
           unspent_output: %UnspentOutput{
             from: from,
             amount: amount,
             type: :UCO,
             reward?: reward?,
             timestamp: %DateTime{} = timestamp
           },
           protocol_version: protocol_version
         },
         false
       ) do
    {:ok, pid} = DB.start_inputs_writer(:UCO, address)

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

    DB.stop_inputs_writer(pid)
  end

  @doc """
  Get the unspent outputs for a given transaction address
  If we reached the threshold, we will read from db and return inputs as utxo
  If we did not we just return from ets
  """
  @spec get_unspent_outputs(address :: binary()) :: list(VersionedUnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        []

      [{^address, true}] ->
        :UCO
        |> DB.get_inputs(address)
        |> Enum.reduce([], fn
          %VersionedTransactionInput{
            input: %TransactionInput{
              from: from,
              amount: amount,
              spent?: _,
              type: :UCO,
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
                  type: :UCO,
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
        build_utxos(inputs)
    end
  end

  defp build_utxos(inputs) do
    inputs
    |> Enum.reduce([], fn {address, from}, acc ->
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
  Retrieve the entire inputs for a given address (spent or unspent)
  """
  @spec get_inputs(binary()) :: list(VersionedTransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    case :ets.lookup(@unspent_output_index_table, address) do
      [] ->
        DB.get_inputs(:UCO, address)

      [{^address, true}] ->
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

  @doc """
  Spend all the unspent outputs for the given address.
  """
  @spec spend_all_unspent_outputs(address :: binary(), from_init? :: boolean()) :: :ok
  def spend_all_unspent_outputs(address, from_init?) do
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
    {:ok, pid} = DB.start_inputs_writer(:UCO, address)

    Enum.each(inputs, fn {to, from} ->
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

      :ets.delete(@ledger_table, to)
    end)

    :ets.delete(@unspent_output_index_table, address)

    DB.stop_inputs_writer(pid)
  end

  defp write_to_db(address, inputs, true) do
    Enum.each(inputs, fn {to, _from} ->
      :ets.delete(@ledger_table, to)
    end)

    :ets.delete(@unspent_output_index_table, address)
  end
end
