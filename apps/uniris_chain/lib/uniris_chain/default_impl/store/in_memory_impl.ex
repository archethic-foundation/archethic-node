defmodule UnirisChain.DefaultImpl.Store.InMemoryImpl do
  @moduledoc false
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.Data.Ledger
  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.Transfer

  use GenServer

  @behaviour UnirisChain.DefaultImpl.Store.Impl

  def start_link(_opts) do
    GenServer.start(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok,
     %{
       device_shared_keys: [],
       unspent_outputs: %{},
       transactions: %{},
       chain_lookup: %{}
     }}
  end

  def handle_call({:get_transaction, address}, _, state = %{transactions: txs}) do
    {:reply, Map.get(txs, address), state}
  end

  def handle_call(
        {:get_transaction_chain, address},
        _from,
        state = %{chain_lookup: chain_lookup, transactions: txs}
      ) do
    chain =
      case Map.get(chain_lookup, address) do
        [] ->
          []

        addresses ->
          Enum.map(addresses, &Map.get(txs, &1))
      end

    {:reply, chain, state}
  end

  def handle_call({:get_transaction_chain, _}, _from, state) do
    {:reply, [], state}
  end

  def handle_call(
        {:get_unspent_output_transactions, address},
        _from,
        state = %{unspent_outputs: utxos, ransaction: txs}
      ) do
    utxos =
      case Map.get(utxos, address) do
        [] ->
          []

        addresses ->
          Enum.map(addresses, &Map.get(txs, &1))
      end

    {:reply, utxos, state}
  end

  def handle_call(
        :get_last_node_shared_secret_transaction,
        _from,
        state = %{transaction: txs}
      ) do
    case Map.get(state, :node_shared_secret_tx) do
      nil ->
        {:reply, nil, state}

      address ->
        {:reply, Map.get(txs, address), state}
    end
  end

  def handle_call(
        :list_device_shared_secret_transactions,
        _from,
        state = %{device_shared_keys: addresses, transactions: txs}
      ) do
    txs = Enum.map(addresses, &Map.get(txs, &1))
    {:reply, txs, state}
  end

  def handle_cast({:store_transaction, tx}, state) do
    {:noreply, build_lookup([tx], state)}
  end

  defp build_lookup(
         txs = [
           tx = %Transaction{
             address: genesis,
             type: type,
             data: %Data{ledger: %Ledger{uco: %UCO{transfers: uco_transfers}}}
           }
           | _
         ],
         state
       ) do
    new_state =
      state
      |> put_in([:transactions, genesis], tx)
      |> put_in([:chain_lookup, genesis], Enum.map(txs, & &1.address))

    case type do
      :node_shared_secret ->
        Map.put(new_state, :node_shared_secret, tx.address)

      :device_shared_secret ->
        Map.update!(new_state, :device_shared_secret, &(&1 ++ [tx.address]))

      :transfer ->
        Enum.reduce(uco_transfers, new_state, fn %Transfer{to: recipient} ->
          put_in(new_state, [:unspent_outputs, recipient], &(&1 ++ [tx.address]))
        end)
    end
  end

  def handle_cast(
        {:store_transaction_chain, txs},
        state
      ) do
    {:noreply, build_lookup(txs, state)}
  end

  @spec get_transaction(binary()) :: Transaction.validated()
  def get_transaction(address) do
    case GenServer.call(__MODULE__, {:get_transaction, address}) do
      tx = %Transaction{} ->
        tx

      nil ->
        raise "Transaction not exists"
    end
  end

  @spec get_transaction_chain(binary()) :: list(Transaction.validated())
  def get_transaction_chain(address) do
    GenServer.call(__MODULE__, {:get_transaction_chain, address})
  end

  @spec get_unspent_output_transactions(binary()) :: list(Transaction.validated())
  def get_unspent_output_transactions(address) do
    GenServer.call(__MODULE__, {:get_unspent_output_transactions, address})
  end

  @spec get_last_node_shared_secret_transaction() :: Transaction.validated()
  def get_last_node_shared_secret_transaction() do
    case GenServer.call(__MODULE__, :get_last_node_shared_secret_transaction) do
      tx = %Transaction{} ->
        tx

      nil ->
        raise "Transaction not exists"
    end
  end

  @spec list_device_shared_secret_transactions() :: list(Transaction.validated())
  def list_device_shared_secret_transactions() do
    GenServer.call(__MODULE__, :list_device_shared_secret_transactions)
  end

  @spec store_transaction(Transaction.validated()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    GenServer.cast(__MODULE__, {:store_transaction, tx})
  end

  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    GenServer.cast(__MODULE__, {:store_transaction_chain, txs})
  end
end
