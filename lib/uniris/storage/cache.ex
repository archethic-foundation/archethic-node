defmodule Uniris.Storage.Cache do
  @moduledoc false

  alias Uniris.Crypto
  alias Uniris.Storage.Backend

  alias Uniris.Transaction
  alias Uniris.Transaction.ValidationStamp
  alias Uniris.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionData
  alias Uniris.TransactionInput

  @node_table :uniris_node_tx
  @ledger_table :uniris_ledger
  @shared_secrets_table :uniris_shared_secrets_txs
  @ko_transaction_table :uniris_ko_txs
  @chain_track_table :uniris_chain_tracking
  @latest_transactions_table :uniris_latest_tx
  @transaction_chain_length :uniris_chain_length
  @code_table :uniris_code_tx
  @pending_table :uniris_pending_tx

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@node_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@ledger_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@ko_transaction_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@shared_secrets_table, [:bag, :named_table, :public, read_concurrency: true])
    :ets.new(@chain_track_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@transaction_chain_length, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@code_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@pending_table, [:set, :named_table, :public, read_concurrency: true])

    :ets.new(@latest_transactions_table, [
      :ordered_set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    Enum.each(Backend.list_transaction_chains_info(), fn {last_tx, size} ->
      set_transaction_length(last_tx.address, size)

      Backend.get_transaction_chain(last_tx.address)
      |> Enum.each(fn tx ->
        track_transaction(tx)
        index_transaction(tx)
        set_ledger(tx)
      end)
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

  defp index_transaction(%Transaction{address: tx_address, type: :code_proposal}) do
    :ets.insert(@pending_table, {tx_address, []})
    :ets.insert(@code_table, {tx_address, []})
  end

  defp index_transaction(%Transaction{
         address: tx_address,
         type: :code_approval,
         data: %TransactionData{recipients: [proposal_address]}
       }) do
    case :ets.lookup(@pending_table, proposal_address) do
      [{_, signatures}] ->
        :ets.insert(@pending_table, {proposal_address, [tx_address | signatures]})
        [{_, approvals}] = :ets.lookup(@code_table, proposal_address)
        :ets.insert(@code_table, {proposal_address, [tx_address | approvals]})
    end
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

  @doc """
  Index transaction, update its ledger and update the chain tracker
  """
  @spec store_transaction(Transaction.t()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    :ets.delete(@ko_transaction_table, tx.address)
    track_transaction(tx)
    index_transaction(tx)
    set_ledger(tx)
    :ok
  end

  @doc """
  Mark a transaction KO and specifies its inconsitencies
  """
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

  @doc """
  List the node transactions addresses
  """
  @spec list_node_transaction_addresses() :: list(binary)
  def list_node_transaction_addresses do
    :ets.select(@node_table, [{{:_, :"$1"}, [], [:"$1"]}])
  end

  @doc """
  List the origin shared secrets transactions addresses
  """
  @spec list_origin_shared_secrets_addresses() :: list(binary())
  def list_origin_shared_secrets_addresses do
    case :ets.lookup(@shared_secrets_table, :origin_shared_secrets) do
      [] ->
        []

      transactions ->
        Enum.map(transactions, fn {_, address} ->
          address
        end)
    end
  end

  @doc """
  Determines if a transaction is ko
  """
  @spec ko_transaction?(binary()) :: boolean()
  def ko_transaction?(address) do
    case :ets.lookup(@ko_transaction_table, address) do
      [] ->
        false

      _ ->
        true
    end
  end

  @doc """
  Get the unspent outputs for a given transaction address
  """
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

  @doc """
  Retrieve the last node shared secret transaction address
  """
  @spec get_last_node_shared_secrets_address() :: {:ok, binary()} | {:error, :not_found}
  def get_last_node_shared_secrets_address do
    case :ets.lookup(@shared_secrets_table, :last_node_shared_secrets) do
      [{_, address}] ->
        {:ok, address}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Retrieve the last transaction address for a chain
  """
  @spec get_last_transaction_address(binary()) :: {:ok, binary()} | {:error, :not_found}
  def get_last_transaction_address(address) do
    case :ets.lookup(@chain_track_table, address) do
      [] ->
        {:error, :not_found}

      [{previous, next}] when previous == next ->
        {:ok, address}

      [{_, next}] ->
        get_last_transaction_address(next)
    end
  end

  @doc """
  Retrieve the ledger balance for a given address using the unspent outputs
  """
  @spec get_ledger_balance(binary()) :: float()
  def get_ledger_balance(address) do
    @ledger_table
    |> :ets.lookup(address)
    |> Enum.filter(fn {_, _, spent} -> spent == false end)
    |> Enum.reduce(0.0, fn {_, %UnspentOutput{amount: amount}, _}, acc -> acc + amount end)
  end

  @doc """
  Retrieve the entire inputs for a given address (spent or unspent)
  """
  @spec get_ledger_inputs(binary()) :: list(TransactionInput.t())
  def get_ledger_inputs(address) do
    @ledger_table
    |> :ets.lookup(address)
    |> Enum.map(fn {_, utxo, spent?} ->
      %TransactionInput{
        from: utxo.from,
        amount: utxo.amount,
        spent?: spent?
      }
    end)
    |> Enum.reject(&(&1.from == address))
  end

  @doc """
  The the depth of a transaction chain
  """
  @spec set_transaction_length(binary(), non_neg_integer()) :: :ok
  def set_transaction_length(address, length) do
    true = :ets.insert(@transaction_chain_length, {address, length})
    :ok
  end

  @doc """
  Find out the depth of a transaction chain
  """
  @spec get_transaction_chain_length(binary()) :: non_neg_integer()
  def get_transaction_chain_length(address) do
    case :ets.lookup(@transaction_chain_length, address) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end

  @doc """
  List the code proposal transaction addresses
  """
  @spec list_code_proposals_addresses() :: list(binary())
  def list_code_proposals_addresses do
    :ets.select(@code_table, [{{:"$1", :_}, [], [:"$1"]}])
  end

  @doc """
  Get the counter signatures for the pending transaction address
  """
  @spec get_pending_transaction_signatures(binary()) :: list(binary())
  def get_pending_transaction_signatures(address) do
    case :ets.lookup(@pending_table, address) do
      [{_, signatures}] ->
        signatures

      _ ->
        []
    end
  end
end
