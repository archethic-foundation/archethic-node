defmodule Uniris.DB.KeyValueImpl do
  @moduledoc false

  use GenServer

  alias Uniris.DBImpl

  alias Uniris.TransactionChain.Transaction
  alias Uniris.Utils

  @behaviour DBImpl

  @db_name :kv_db

  @doc """
  Initialize the KV store
  """
  @spec start_link(Keyword.t()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl DBImpl
  @doc """
  Retrieve a transaction by address and project the requested fields
  """
  @spec get_transaction(binary(), fields :: list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    case CubDB.get(get_db(), {"transaction", address}) do
      nil ->
        {:error, :transaction_not_exists}

      tx ->
        tx =
          tx
          |> Transaction.to_map()
          |> Utils.take_in(fields)
          |> Transaction.from_map()

        {:ok, tx}
    end
  end

  @impl DBImpl
  @doc """
  Fetch the transaction chain by address and project the requested fields from the transactions
  """
  @spec get_transaction_chain(binary(), list()) :: Enumerable.t()
  def get_transaction_chain(address, fields \\ []) when is_binary(address) and is_list(fields) do
    db = get_db()

    Stream.resource(
      fn -> CubDB.get(db, {"chain", address}) end,
      fn
        nil ->
          {:halt, []}

        [] ->
          {:halt, []}

        [address | rest] ->
          tx =
            db
            |> CubDB.get({"transaction", address})
            |> Transaction.to_map()
            |> Utils.take_in(fields)
            |> Transaction.from_map()

          {[tx], rest}
      end,
      fn _ -> :ok end
    )
  end

  @impl DBImpl
  @doc """
  Store the transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(tx = %Transaction{address: address}) do
    :ok = CubDB.put(get_db(), {"transaction", address}, tx)
  end

  @impl DBImpl
  @doc """
  Store the transactions and store the chain links
  """
  @spec write_transaction_chain(Enumerable.t()) :: :ok
  def write_transaction_chain(chain) do
    db = get_db()

    %Transaction{address: chain_address} = Enum.at(chain, 0)

    chain
    |> Stream.each(&CubDB.put(db, {"transaction", &1.address}, &1))
    |> Stream.run()

    transaction_addresses =
      chain
      |> Stream.map(& &1.address)
      |> Enum.to_list()

    :ok = CubDB.put(db, {"chain", chain_address}, transaction_addresses)
  end

  @doc """
  Reference a last address from a previous address
  """
  @impl DBImpl
  @spec add_last_transaction_address(binary(), binary()) :: :ok
  def add_last_transaction_address(tx_address, last_address) do
    :ok = CubDB.put(get_db(), {"chain_lookup", tx_address}, last_address)
  end

  @doc """
  List the last transaction lookups
  """
  @impl DBImpl
  @spec list_last_transaction_addresses() :: Enumerable.t()
  def list_last_transaction_addresses do
    {:ok, lookup} =
      CubDB.select(get_db(),
        pipe: [
          filter: fn {key, _} -> match?({"chain_lookup", _}, key) end,
          map: fn {{"chain_lookup", address}, last_address} -> {address, last_address} end
        ]
      )

    lookup
  end

  @impl DBImpl
  @doc """
  List the transactions
  """
  @spec list_transactions(list()) :: Enumerable.t()
  def list_transactions(fields \\ []) when is_list(fields) do
    {:ok, txs} =
      CubDB.select(get_db(),
        pipe: [
          filter: fn {key, _} ->
            match?({"transaction", _}, key)
          end,
          map: fn {_, tx} ->
            tx
            |> Transaction.to_map()
            |> Utils.take_in(fields)
            |> Transaction.from_map()
          end
        ]
      )

    txs
  end

  @impl DBImpl
  def migrate do
    :ok
  end

  @impl GenServer
  def init(opts) do
    root_dir = Keyword.get(opts, :root_dir, Application.app_dir(:uniris, "priv/storage"))
    {:ok, db} = CubDB.start_link(root_dir)

    :persistent_term.put(@db_name, db)
    {:ok, %{db: db}}
  end

  defp get_db, do: :persistent_term.get(@db_name)
end
