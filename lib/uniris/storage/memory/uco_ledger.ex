defmodule Uniris.Storage.Memory.UCOLedger do
  @moduledoc false

  @uco_utxo_table :uco_ledger
  @uco_utxo_index_table :utxo_index

  alias Uniris.Crypto

  alias Uniris.Storage.Backend, as: DB

  alias Uniris.Transaction

  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Uniris.TransactionInput

  use GenServer

  require Logger

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    Logger.info("Initialize InMemory UCO Ledger...")

    :ets.new(@uco_utxo_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@uco_utxo_index_table, [:bag, :named_table, :public, read_concurrency: true])

    query_fields = [
      :address,
      :previous_public_key,
      validation_stamp: [
        ledger_operations: [:unspent_outputs, :node_movements, :transaction_movements]
      ]
    ]

    DB.list_transactions(query_fields)
    |> Stream.each(&distribute_unspent_outputs/1)
    |> Stream.run()

    {:ok, []}
  end

  @doc """
  Allocate the funds coming from a transaction (transfers, node movements, mutate the spent ucos)
  """
  @spec distribute_unspent_outputs(Transaction.t()) :: :ok
  def distribute_unspent_outputs(%Transaction{
        address: address,
        previous_public_key: previous_public_key,
        validation_stamp: %ValidationStamp{
          ledger_operations: %LedgerOperations{
            unspent_outputs: utxos,
            node_movements: node_movements,
            transaction_movements: transaction_movements
          }
        }
      }) do
    spend_funds(previous_public_key)

    # Set transfers unspent outputs
    Enum.each(
      transaction_movements,
      &add_utxo(&1.to, %UnspentOutput{amount: &1.amount, from: address})
    )

    # Set transaction chain unspent outputs
    Enum.each(utxos, &add_utxo(address, &1))

    # Set node rewards
    Enum.each(
      node_movements,
      &add_utxo(Crypto.hash(&1.to), %UnspentOutput{amount: &1.amount, from: address})
    )
  end

  defp spend_funds(previous_public_key) do
    previous_address = Crypto.hash(previous_public_key)

    @uco_utxo_index_table
    |> :ets.lookup(previous_address)
    |> Enum.each(fn {_, from} ->
      :ets.update_element(@uco_utxo_table, {previous_address, from}, {3, true})
    end)

    :ets.delete(@uco_utxo_index_table, previous_address)
  end

  defp add_utxo(to, %UnspentOutput{from: from, amount: amount}) do
    :ets.insert(@uco_utxo_table, {{to, from}, amount, false})
    :ets.insert(@uco_utxo_index_table, {to, from})
  end

  @doc """
  Get the unspent outputs for a given transaction address
  """
  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def get_unspent_outputs(address) when is_binary(address) do
    @uco_utxo_index_table
    |> :ets.lookup(address)
    |> Enum.reduce([], fn {_, from}, acc ->
      case :ets.lookup(@uco_utxo_table, {address, from}) do
        [{_, amount, false}] ->
          [
            %UnspentOutput{
              from: from,
              amount: amount
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
  @spec get_inputs(binary()) :: list(TransactionInput.t())
  def get_inputs(address) when is_binary(address) do
    @uco_utxo_index_table
    |> :ets.lookup(address)
    |> Enum.reduce([], fn {_, from}, acc ->
      if from == address do
        acc
      else
        [{_, amount, spent?}] = :ets.lookup(@uco_utxo_table, {address, from})

        [
          %TransactionInput{
            from: from,
            amount: amount,
            spent?: spent?
          }
          | acc
        ]
      end
    end)
  end

  @doc """
  Returns the balance of UCO for an address
  """
  @spec balance(binary()) :: float()
  def balance(address) when is_binary(address) do
    address
    |> get_unspent_outputs()
    |> Enum.reduce(0.0, &(&2 + &1.amount))
  end
end
