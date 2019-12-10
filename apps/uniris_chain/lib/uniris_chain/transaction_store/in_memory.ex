defmodule UnirisChain.TransactionStore.InMemory do
  @moduledoc false
  alias UnirisChain.TransactionStore
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data
  alias UnirisCrypto, as: Crypto

  use GenServer

  @behaviour TransactionStore

  def start_link(_opts) do
    GenServer.start(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    {:ok,
     %{
       transactions: %{},
       chain_lookup: %{},
       last_node_shared_key_tx: nil
     }, {:continue, :genesis_shared_transaction}}
  end

  @impl GenServer
  def handle_continue(:genesis_shared_transaction, state) do
    with {:ok, last_pub} <- Crypto.last_public_key(:node) do
      aes_key = :crypto.strong_rand_bytes(32)
      {:ok, enc_aes_key} = Crypto.ec_encrypt(aes_key, last_pub)
      enc_node_keys = Map.new() |> Map.put(last_pub, enc_aes_key)

      enc_new_keys =
        Crypto.aes_encrypt(
          %{daily: Application.get_env(:uniris_chain, :genesis_daily_nonce)},
          aes_key
        )

      node_shared_key_tx = %Transaction{
        address:
          <<4, 143, 35, 132, 108, 91, 231, 48, 159, 167, 39, 196, 183, 253, 154, 66, 211, 98, 222,
            73, 153, 64, 207, 229, 160, 74, 87, 173, 255, 146, 30, 148, 27, 153, 52, 88, 165, 51,
            109, 75, 23, 62, 151, 234, 5, 28, 235, 216, 52, 173, 240, 76, 183, 55, 37, 220, 71,
            136, 166, 203, 97, 66, 158, 95, 26>>,
        timestamp: DateTime.utc_now(),
        type: :node_shared_key,
        data: %Data{
          keys: %{
            enc_node_keys: enc_node_keys,
            enc_new_keys: enc_new_keys
          }
        },
        previous_public_key:
          <<0, 34, 47, 225, 49, 180, 197, 236, 137, 249, 196, 28, 129, 131, 37, 198, 46, 183, 225,
            216, 205, 248, 159, 153, 170, 80, 12, 112, 34, 30, 195, 13, 127>>,
        previous_signature: "",
        origin_signature: ""
      }

      state =
        state
        |> put_in([:transactions, node_shared_key_tx.address], node_shared_key_tx)
        |> put_in([:chain_lookup, node_shared_key_tx.address], [node_shared_key_tx.address])
        |> Map.put(:last_node_shared_key_tx, node_shared_key_tx)

      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call({:get_transaction, address}, _, state = %{transactions: txs}) do
    {:reply, Map.get(txs, address), state}
  end

  def handle_call(
        {:get_transaction_chain, address},
        _,
        state = %{chain_lookup: chain_lookup, transactions: txs}
      ) do
    case Map.get(chain_lookup, address) do
      nil ->
        {:reply, {:error, :transaction_chain_not_exists}, state}

      txs ->
        {:reply, Enum.map(txs, &Map.get(txs, &1)), state}
    end
  end

  @impl GenServer
  def handle_call(
        :get_last_node_shared_key_transaction,
        _,
        state = %{last_node_shared_key_tx: tx}
      ) do
    {:reply, tx, state}
  end

  @impl GenServer
  def handle_cast({:store_transaction_chain, txs}, state) do
    state =
      Enum.reduce(txs, state, fn tx, state ->
        Map.put(state.transactions, tx.address, tx)
      end)

    state = put_in(state, [:chain_lookup, List.first(txs).address], txs)
    {:noreply, state}
  end

  @impl TransactionStore
  @spec get_transaction(binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exist}
  def get_transaction(address) when is_binary(address) do
    case GenServer.call(__MODULE__, {:get_transaction, address}) do
      nil ->
        {:error, :transaction_not_exists}

      tx = %Transaction{} ->
        {:ok, tx}
    end
  end

  @impl TransactionStore
  @spec get_transaction_chain(binary()) ::
          {:ok, list(Transaction.validated())}
          | {:error, :chain_not_exists}
  def get_transaction_chain(address) when is_binary(address) do
    case GenServer.call(__MODULE__, {:get_transaction_chain, address}) do
      {:error, :transaction_chain_not_exists} ->
        {:error, :transaction_chain_not_exists}

      chain ->
        {:ok, chain}
    end
  end

  @impl TransactionStore
  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    GenServer.cast(__MODULE__, {:store_transaction_chain, txs})
  end

  @impl TransactionStore
  @spec get_last_node_shared_key_transaction() :: Transaction.validated()
  def get_last_node_shared_key_transaction() do
    GenServer.call(__MODULE__, :get_last_node_shared_key_transaction)
  end
end
