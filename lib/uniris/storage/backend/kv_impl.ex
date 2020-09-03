defmodule Uniris.Storage.KeyValueBackend do
  @moduledoc false

  use GenServer

  alias Uniris.Storage.BackendImpl

  @behaviour BackendImpl

  alias Uniris.Transaction

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl BackendImpl
  def migrate do
    :ok
  end

  @impl GenServer
  def init(_) do
    root_dir =
      :uniris
      |> Application.get_env(__MODULE__, root_dir: Application.app_dir(:uniris, "priv/storage"))
      |> Keyword.fetch!(:root_dir)

    {:ok, db} = CubDB.start_link(root_dir)
    {:ok, %{db: db}}
  end

  @impl GenServer
  def handle_call({:get_transaction, address, fields}, _, state = %{db: db}) do
    case CubDB.get(db, {"transaction", address}) do
      nil ->
        {:reply, nil, state}

      tx ->
        tx =
          tx
          |> Transaction.to_map()
          |> take_in(fields)
          |> Transaction.from_map()

        {:reply, tx, state}
    end
  end

  def handle_call({:get_transaction_chain, address, fields}, _, state = %{db: db}) do
    chain =
      db
      |> CubDB.get({"chain", address})
      |> case do
        nil ->
          []

        addresses ->
          Enum.map(addresses, fn address ->
            db
            |> CubDB.get({"transaction", address})
            |> Transaction.to_map()
            |> take_in(fields)
            |> Transaction.from_map()
          end)
      end

    {:reply, chain, state}
  end

  def handle_call({:write_transaction, tx}, _, state = %{db: db}) do
    do_write_transaction(db, tx)
    {:reply, :ok, state}
  end

  def handle_call(
        {:write_transaction_chain, chain = [%Transaction{address: chain_address} | _]},
        _,
        state = %{db: db}
      ) do
    transaction_addresses = Enum.map(chain, & &1.address)

    values = [
      {{"chain", chain_address}, transaction_addresses},
      {{"chain_length", chain_address}, length(transaction_addresses)}
    ]

    Enum.each(chain, &do_write_transaction(db, &1))

    :ok = CubDB.put_multi(db, values)
    {:reply, :ok, state}
  end

  def handle_call({:list_transactions, fields}, _, state = %{db: db}) do
    {:ok, txs} =
      CubDB.select(db,
        pipe: [
          filter: fn {key, _} ->
            match?({"transaction", _}, key)
          end,
          map: fn {_, tx} ->
            tx
            |> Transaction.to_map()
            |> take_in(fields)
            |> Transaction.from_map()
          end
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

  def handle_call({:list_transactions, type, fields}, _, state = %{db: db}) do
    keys =
      case CubDB.get(db, {"transaction_type", Atom.to_string(type)}) do
        nil ->
          []

        transactions ->
          Enum.map(transactions, fn address -> {"transaction", address} end)
      end

    transactions =
      CubDB.get_multi(db, keys)
      |> Stream.map(fn {_, tx} ->
        tx
        |> Transaction.to_map()
        |> take_in(fields)
        |> Transaction.from_map()
      end)

    {:reply, transactions, state}
  end

  defp do_write_transaction(db, tx = %Transaction{type: type, address: address}) do
    :ok = CubDB.put(db, {"transaction", address}, tx)
    :ok = CubDB.update(db, {"transaction_type", Atom.to_string(type)}, [address], &[address | &1])
  end

  @impl BackendImpl
  @spec get_transaction(binary(), fields :: list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_list(fields) do
    case GenServer.call(__MODULE__, {:get_transaction, address, fields}) do
      tx = %Transaction{} ->
        {:ok, tx}

      nil ->
        {:error, :transaction_not_exists}
    end
  end

  @impl BackendImpl
  @spec get_transaction_chain(binary(), list()) :: list(Transaction.t())
  def get_transaction_chain(address, fields \\ []) when is_list(fields) do
    GenServer.call(__MODULE__, {:get_transaction_chain, address, fields})
  end

  @impl BackendImpl
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    GenServer.call(__MODULE__, {:write_transaction, tx})
  end

  @impl BackendImpl
  @spec write_transaction_chain(list(Transaction.t())) :: :ok
  def write_transaction_chain(txs) when is_list(txs) do
    GenServer.call(__MODULE__, {:write_transaction_chain, txs})
  end

  @impl BackendImpl
  @spec list_transactions(list()) :: Enumerable.t()
  def list_transactions(fields \\ []) when is_list(fields) do
    GenServer.call(__MODULE__, {:list_transactions, fields})
  end

  @impl BackendImpl
  @spec list_transaction_chains_info() :: Enumerable.t()
  def list_transaction_chains_info do
    GenServer.call(__MODULE__, :list_transaction_chains_info)
  end

  @impl BackendImpl
  @spec list_transactions_by_type(type :: Transaction.type(), fields :: list()) :: Enumerable.t()
  def list_transactions_by_type(type, fields \\ []) do
    GenServer.call(__MODULE__, {:list_transactions, type, fields})
  end

  defp take_in(map = %{}, []), do: map

  defp take_in(map = %{}, fields) when is_list(fields) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      case v do
        %{} ->
          Map.put(acc, k, take_in(v, Keyword.get(fields, k, [])))

        _ ->
          do_take_in(acc, map, k, fields)
      end
    end)
  end

  defp do_take_in(acc, map, key, fields) do
    if key in fields do
      Map.put(acc, key, Map.get(map, key))
    else
      acc
    end
  end
end
