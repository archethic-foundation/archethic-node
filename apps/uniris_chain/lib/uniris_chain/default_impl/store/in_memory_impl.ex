defmodule UnirisChain.DefaultImpl.Store.InMemoryImpl do
  @moduledoc false
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.Transfer

  use GenServer

  @behaviour UnirisChain.DefaultImpl.Store.Impl

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok,
     %{
       unspent_outputs: %{},
       transactions: %{},
       chain_lookup: %{}
     }}
  end

  @impl true
  def handle_call({:get_transaction, address}, _, state = %{transactions: txs}) do
    {:reply, Map.get(txs, address), state}
  end

  def handle_call(
        {:get_transaction_chain, address},
        _from,
        state = %{chain_lookup: chain_lookup, transactions: txs}
      ) do
    case Map.get(chain_lookup, address) do
      nil ->
        {:reply, [], state}

      addresses ->
        {:reply, Enum.map(addresses, &Map.get(txs, &1)), state}
    end
  end

  def handle_call(
        {:get_unspent_output_transactions, address},
        _from,
        state = %{unspent_outputs: utxos, transactions: txs}
      ) do
    utxos =
      case Map.get(utxos, address) do
        nil ->
          []

        addresses ->
          Enum.map(addresses, &Map.get(txs, &1))
      end

    {:reply, utxos, state}
  end

  def handle_call(
        :get_last_node_shared_secrets_transaction,
        _from,
        state = %{transactions: txs}
      ) do
    case Map.get(state, :node_shared_secrets_tx) do
      nil ->
        {:reply, nil, state}

      address ->
        {:reply, Map.get(txs, address), state}
    end
  end

  @impl true
  def handle_cast({:store_transaction, tx}, state) do
    {:noreply, build_lookup([tx], state)}
  end

  def handle_cast(
        {:store_transaction_chain, txs},
        state
      ) do
    {:noreply, build_lookup(txs, state)}
  end

  defp build_lookup(
         txs = [%Transaction{} | []],
         state
       ) do
    do_build_lookup(txs, state)
  end

  defp build_lookup(
         txs = [%Transaction{address: last_address} | _],
         state
       ) do
    do_build_lookup(
      txs,
      put_in(state, [:chain_lookup, last_address], Enum.map(txs, & &1.address))
    )
  end

  defp do_build_lookup(txs = [tx = %Transaction{address: last_address, type: type} | _], state) do
    %Transaction{address: genesis_address} = List.last(txs)

    new_state =
      Enum.reduce(txs, state, fn tx, acc ->
        put_in(acc, [:transactions, tx.address], tx)
      end)
      |> put_in([:chain_lookup, genesis_address], Enum.map(txs, & &1.address))
      |> put_in([:chain_lookup, last_address], Enum.map(txs, & &1.address))

    new_state = do_build_lookup_unspent_outputs(tx, new_state)

    case type do
      :node_shared_secrets ->
        Map.put(new_state, :node_shared_secrets_tx, tx.address)

      _ ->
        new_state
    end
  end

  defp do_build_lookup_unspent_outputs(tx = %Transaction{data: %Data{ledger: ledger}}, state) do
    case ledger do
      %{uco: %UCO{transfers: uco_transfers}} ->
        Enum.reduce(uco_transfers, state, fn %Transfer{to: recipient}, acc ->
          update_in(acc, [:unspent_outputs, recipient], fn utxo ->
            case utxo do
              nil ->
                [tx.address]

              _ ->
                utxo ++ [tx.address]
            end
          end)
        end)

      _ ->
        state
    end
  end

  @impl true
  @spec get_transaction(binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_transaction(address) do
    case GenServer.call(__MODULE__, {:get_transaction, address}) do
      tx = %Transaction{} ->
        {:ok, tx}

      nil ->
        {:error, :transaction_not_exists}
    end
  end

  @impl true
  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :transaction_chain_not_exists}
  def get_transaction_chain(address) do
    case GenServer.call(__MODULE__, {:get_transaction_chain, address}) do
      [] ->
        {:error, :transaction_chain_not_exists}

      chain ->
        {:ok, chain}
    end
  end

  @impl true
  @spec get_unspent_output_transactions(binary()) ::
          {:ok, list(Transaction.validated())} | {:error, :unspent_output_transactions_not_exists}
  def get_unspent_output_transactions(address) do
    case GenServer.call(__MODULE__, {:get_unspent_output_transactions, address}) do
      [] ->
        {:error, :unspent_output_transactions_not_exists}

      utxo ->
        {:ok, utxo}
    end
  end

  @impl true
  @spec get_last_node_shared_secrets_transaction() ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def get_last_node_shared_secrets_transaction() do
    case GenServer.call(__MODULE__, :get_last_node_shared_secrets_transaction) do
      tx = %Transaction{} ->
        {:ok, tx}

      nil ->
        {:error, :transaction_not_exists}
    end
  end

  @impl true
  @spec store_transaction(Transaction.validated()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    GenServer.cast(__MODULE__, {:store_transaction, tx})
  end

  @impl true
  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    GenServer.cast(__MODULE__, {:store_transaction_chain, txs})
  end
end
