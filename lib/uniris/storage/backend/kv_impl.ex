defmodule Uniris.Storage.KeyValueBackend do
  @moduledoc false

  use GenServer

  @behaviour Uniris.Storage.BackendImpl

  alias Uniris.Transaction

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    root_dir = Application.app_dir(:uniris, Application.get_env(:uniris, __MODULE__)[:root_dir])
    {:ok, db} = CubDB.start_link(root_dir)
    {:ok, %{db: db}}
  end

  @impl true
  def handle_call({:get_transaction, address}, _, state = %{db: db}) do
    tx = CubDB.get(db, {"transaction", address})
    {:reply, tx, state}
  end

  def handle_call({:get_transaction_chain, address}, _, state = %{db: db}) do
    chain =
      db
      |> CubDB.get({"chain", address})
      |> case do
        nil ->
          []

        addresses ->
          Enum.map(addresses, &CubDB.get(db, {"transaction", &1}))
      end

    {:reply, chain, state}
  end

  def handle_call({:write_transaction, tx}, _, state = %{db: db}) do
    CubDB.put(db, {"transaction", tx.address}, tx)
    {:reply, :ok, state}
  end

  def handle_call(
        {:write_transaction_chain, chain = [%Transaction{address: chain_address} | _]},
        _,
        state = %{db: db}
      ) do
    transaction_addresses = Enum.map(chain, & &1.address)

    values =
      Enum.reduce(
        chain,
        [
          {{"chain", chain_address}, transaction_addresses},
          {{"chain_length", chain_address}, length(transaction_addresses)}
        ],
        fn tx, acc ->
          [{{"transaction", tx.address}, tx} | acc]
        end
      )

    :ok = CubDB.put_multi(db, values)
    {:reply, :ok, state}
  end

  def handle_call(:list_transactions, _, state = %{db: db}) do
    {:ok, txs} =
      CubDB.select(db,
        pipe: [
          filter: fn {key, _} -> match?({"transaction", _}, key) end,
          map: fn {_, tx} -> tx end
        ]
      )

    {:reply, txs, state}
  end

  def handle_call(:list_transaction_chains_info, _, state = %{db: db}) do
    {:ok, infos} =
      CubDB.select(db,
        pipe: [
          filter: fn {key, _} ->
            match?({"chain_length", _}, key)
          end,
          map: fn {{"chain_length", address}, nb} ->
            {address, nb}
          end
        ]
      )

    {:reply, infos, state}
  end

  @impl true
  @spec get_transaction(binary()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address) do
    case GenServer.call(__MODULE__, {:get_transaction, address}) do
      tx = %Transaction{} ->
        {:ok, tx}

      nil ->
        {:error, :transaction_not_exists}
    end
  end

  @impl true
  @spec get_transaction_chain(binary()) :: list(Transaction.t())
  def get_transaction_chain(address) do
    GenServer.call(__MODULE__, {:get_transaction_chain, address})
  end

  @impl true
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    GenServer.call(__MODULE__, {:write_transaction, tx})
  end

  @impl true
  @spec write_transaction_chain(list(Transaction.t())) :: :ok
  def write_transaction_chain(txs) when is_list(txs) do
    GenServer.call(__MODULE__, {:write_transaction_chain, txs})
  end

  @impl true
  @spec list_transactions() :: Enumerable.t()
  def list_transactions do
    GenServer.call(__MODULE__, :list_transactions)
  end

  @impl true
  @spec list_transaction_chains_info() :: Enumerable.t()
  def list_transaction_chains_info do
    GenServer.call(__MODULE__, :list_transaction_chains_info)
  end
end
