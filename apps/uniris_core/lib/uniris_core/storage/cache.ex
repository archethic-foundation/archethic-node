defmodule UnirisCore.Storage.Cache do
  @moduledoc false

  alias UnirisCore.Crypto
  alias UnirisCore.Storage.Backend

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  @transaction_table :uniris_txs
  @node_table :uniris_node_tx
  @ledger_table :uniris_ledger
  @shared_secrets_table :uniris_shared_secrets_txs
  @ko_transaction_table :uniris_ko_txs
  @chain_track_table :uniris_chain_tracking
  @latest_transactions_table :uniris_latest_tx
  @transaction_chain_length :uniris_chain_length

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@transaction_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@node_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@ledger_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@ko_transaction_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@shared_secrets_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@chain_track_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@transaction_chain_length, [:set, :named_table, :public, read_concurrency: true])

    :ets.new(@latest_transactions_table, [
      :ordered_set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    Enum.each(Backend.list_transaction_chains_info(), fn {last_tx, size} ->
      :ets.insert(@transaction_table, {last_tx.address, last_tx})
      track_transaction(last_tx)
      index_transaction(last_tx)
      set_ledger(last_tx)
      set_transaction_length(last_tx.address, size)
    end)

    {:ok, []}
  end

  defp index_transaction(%Transaction{
         address: tx_address,
         type: :node,
         previous_public_key: previous_public_key
       }) do
    case :ets.lookup(@node_table, previous_public_key) do
      [] ->
        :ets.insert(@node_table, {previous_public_key, tx_address})

      [{genesis, _}] ->
        :ets.insert(@node_table, {genesis, tx_address})
    end
  end

  defp index_transaction(%Transaction{address: tx_address, type: :node_shared_secrets}) do
    case :ets.lookup(@shared_secrets_table, :first_node_shared_secrets) do
      [] ->
        :ets.insert(@shared_secrets_table, {:last_node_shared_secrets, tx_address})
        :ets.insert(@shared_secrets_table, {:first_node_shared_secrets, tx_address})

      _ ->
        :ets.delete(@shared_secrets_table, :last_node_shared_secrets)
        :ets.insert(@shared_secrets_table, {:last_node_shared_secrets, tx_address})
    end
  end

  defp index_transaction(%Transaction{address: tx_address, type: :origin_shared_secrets}) do
    :ets.insert(@shared_secrets_table, {:origin_shared_secrets, tx_address})
  end

  defp index_transaction(%Transaction{}), do: :ok

  defp set_ledger(%Transaction{
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
    previous_address = Crypto.hash(previous_public_key)
    previous_unspent_outputs = :ets.lookup(@ledger_table, previous_address)
    :ets.delete(@ledger_table, previous_address)

    Enum.each(previous_unspent_outputs, fn {_, utxo, _} ->
      :ets.insert(@ledger_table, {previous_address, utxo, true})
    end)

    # Set transfers unspent outputs
    Enum.each(
      transaction_movements,
      &:ets.insert(
        @ledger_table,
        {&1.to, %UnspentOutput{amount: &1.amount, from: address}, false}
      )
    )

    # Set transaction chain unspent outputs
    Enum.each(utxos, &:ets.insert(@ledger_table, {address, &1, false}))

    # Set node rewards
    Enum.each(
      node_movements,
      &:ets.insert(
        @ledger_table,
        {Crypto.hash(&1.to), %UnspentOutput{amount: &1.amount, from: address}, false}
      )
    )
  end

  defp track_transaction(%Transaction{
         address: next_address,
         timestamp: timestamp,
         previous_public_key: previous_public_key
       }) do
    previous_address = Crypto.hash(previous_public_key)
    :ets.insert(@chain_track_table, {previous_address, next_address})
    :ets.insert(@chain_track_table, {next_address, next_address})

    :ets.insert(
      @latest_transactions_table,
      {DateTime.to_unix(timestamp, :millisecond), next_address}
    )
  end

  @spec store_transaction(Transaction.t()) :: :ok
  def store_transaction(tx = %Transaction{address: tx_address}) do
    :ets.delete(@ko_transaction_table, tx.address)
    true = :ets.insert(@transaction_table, {tx_address, tx})
    track_transaction(tx)
    index_transaction(tx)
    set_ledger(tx)
    :ok
  end

  @spec store_ko_transaction(Transaction.t()) :: :ok
  def store_ko_transaction(%Transaction{
        address: tx_address,
        validation_stamp: validation_stamp,
        cross_validation_stamps: stamps
      }) do
    inconsistencies =
      stamps
      |> Enum.map(& &1.inconsistencies)
      |> Enum.uniq()

    true = :ets.insert(@ko_transaction_table, {tx_address, validation_stamp, inconsistencies})
    :ok
  end

  @spec get_transaction(binary()) :: Transaction.t() | nil
  def get_transaction(tx_address) do
    case :ets.lookup(@transaction_table, tx_address) do
      [{_, tx}] ->
        tx

      _ ->
        nil
    end
  end

  @spec node_transactions() :: list(Transaction.t())
  def node_transactions do
    case :ets.select(@node_table, [{{:_, :"$1"}, [], [:"$1"]}]) do
      [] ->
        []

      addresses ->
        Enum.map(addresses, &get_transaction/1)
    end
  end

  @spec origin_shared_secrets_transactions() :: list(Transaction.t())
  def origin_shared_secrets_transactions do
    case :ets.lookup(@shared_secrets_table, :origin_shared_secrets) do
      [] ->
        []

      transactions ->
        Enum.map(transactions, fn {_, address} ->
          [{_, tx}] = :ets.lookup(@transaction_table, address)
          tx
        end)
    end
  end

  @spec ko_transaction?(binary()) :: boolean()
  def ko_transaction?(address) do
    case :ets.lookup(@ko_transaction_table, address) do
      [] ->
        false

      _ ->
        true
    end
  end

  @spec get_unspent_outputs(binary()) :: list(UnspentOutput.t())
  def get_unspent_outputs(address) do
    case :ets.lookup(@ledger_table, address) do
      [] ->
        []

      unspent_outputs ->
        unspent_outputs
        |> Enum.filter(fn {_, _, spent} -> spent == false end)
        |> Enum.map(fn {_, utxo, _} -> utxo end)
    end
  end

  @spec last_node_shared_secrets_transaction() :: Transaction.t() | nil
  def last_node_shared_secrets_transaction do
    case :ets.lookup(@shared_secrets_table, :last_node_shared_secrets) do
      [{_, address}] ->
        [{_, tx}] = :ets.lookup(@transaction_table, address)
        tx

      _ ->
        nil
    end
  end

  @spec last_transaction_address(binary()) :: {:ok, binary()} | {:error, :not_found}
  def last_transaction_address(address) do
    case :ets.lookup(@chain_track_table, address) do
      [] ->
        {:error, :not_found}

      [{previous, next}] when previous == next ->
        {:ok, address}

      [{_, next}] ->
        last_transaction_address(next)
    end
  end

  @spec list_transactions(limit :: non_neg_integer()) :: Enumerable.t()
  def list_transactions(0) do
    stream_transactions_per_date()
    |> Stream.map(&get_transaction/1)
  end

  def list_transactions(limit) do
    stream_transactions_per_date()
    |> Stream.take(limit)
    |> Stream.map(&get_transaction/1)
  end

  defp stream_transactions_per_date do
    Stream.resource(
      fn -> :ets.last(@latest_transactions_table) end,
      fn
        :"$end_of_table" ->
          {:halt, nil}

        previous_key ->
          [{_, address}] = :ets.lookup(@latest_transactions_table, previous_key)
          {[address], :ets.prev(@latest_transactions_table, previous_key)}
      end,
      fn _ -> :ok end
    )
  end

  @spec get_ledger_balance(binary()) :: float()
  def get_ledger_balance(address) do
    @ledger_table
    |> :ets.lookup(address)
    |> Enum.filter(fn {_, _, spent} -> spent == false end)
    |> Enum.reduce(0.0, fn {_, %UnspentOutput{amount: amount}, _}, acc -> acc + amount end)
  end

  @spec get_ledger_inputs(binary()) :: list(UnspentOutput.t())
  def get_ledger_inputs(address) do
    @ledger_table
    |> :ets.lookup(address)
    |> Enum.map(fn {_, utxo, _} -> utxo end)
  end

  @spec set_transaction_length(binary(), non_neg_integer()) :: :ok
  def set_transaction_length(address, length) do
    true = :ets.insert(@transaction_chain_length, {address, length})
    :ok
  end

  @spec get_transaction_chain_length(binary()) :: non_neg_integer()
  def get_transaction_chain_length(address) do
    case :ets.lookup(@transaction_chain_length, address) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end
end
