defmodule UnirisCore.Storage.FileBackend do
  @moduledoc false

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction

  use GenServer

  @behaviour UnirisCore.Storage.BackendImpl

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    root_dir =
      Path.join(
        Application.app_dir(:uniris_core, "priv/storage"),
        Application.get_env(:uniris_core, UnirisCore.Crypto.SoftwareKeystore)[:seed]
        |> Crypto.hash()
        |> Base.encode16()
      )

    transactions_dir = Path.join(root_dir, "transactions")
    indexes_dir = Path.join(root_dir, "indexes")

    File.mkdir_p!(transactions_dir)
    File.mkdir_p!(indexes_dir)
    {:ok, %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}}
  end

  @impl true
  def handle_call({:get_transaction, address}, _, state = %{transactions_dir: dir}) do
    try do
      {:reply, read_transaction!(dir, Base.encode16(address)), state}
    rescue
      _ ->
        {:reply, nil, state}
    end
  end

  def handle_call(
        {:get_transaction_chain, address},
        _from,
        state = %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}
      ) do
    {:reply, do_get_transaction_chain(transactions_dir, indexes_dir, address), state}
  end

  def handle_call(:list_transactions, _from, state = %{transactions_dir: dir}) do
    {:reply, do_list_transactions(dir), state}
  end

  @impl true
  def handle_call(
        {:write_transaction, tx = %Transaction{}},
        _,
        state = %{transactions_dir: dir}
      ) do
    File.write!(
      Path.join(dir, Base.encode16(tx.address)),
      :erlang.term_to_binary(tx),
      [:write]
    )

    {:reply, :ok, state}
  end

  def handle_call(
        {:write_transaction_chain, txs},
        _,
        state = %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}
      ) do
    Enum.each(txs, fn tx ->
      File.write!(
        Path.join(transactions_dir, Base.encode16(tx.address)),
        :erlang.term_to_binary(tx),
        [:write]
      )
    end)

    File.write!(
      Path.join(indexes_dir, "chain_#{Base.encode16(List.first(txs).address)}"),
      Enum.reduce(txs, [], fn tx, acc -> acc ++ [Base.encode16(tx.address)] end)
      |> Enum.join("\n"),
      [:write]
    )

    {:reply, :ok, state}
  end

  defp do_list_transactions(transactions_dir) do
    case File.ls(transactions_dir) do
      {:ok, files} ->
        txs =
          Enum.map(files, fn file ->
            File.read!(Path.join(transactions_dir, file))
            |> :erlang.binary_to_term()
          end)

        txs

      _ ->
        []
    end
  end

  defp do_get_transaction_chain(transactions_dir, indexes_dir, address) do
    try do
      File.read!(Path.join(indexes_dir, "chain_#{Base.encode16(address)}"))
      |> String.split("\n")
      |> Enum.map(&read_transaction!(transactions_dir, &1))
    rescue
      _ ->
        []
    end
  end

  defp read_transaction!(transactions_dir, address) do
    Path.join(transactions_dir, address)
    |> File.read!()
    |> :erlang.binary_to_term()
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
  @spec write_transaction(Transaction.validated()) :: :ok
  def write_transaction(tx = %Transaction{}) do
    GenServer.call(__MODULE__, {:write_transaction, tx})
  end

  @impl true
  @spec write_transaction_chain(list(Transaction.validated())) :: :ok
  def write_transaction_chain(txs) when is_list(txs) do
    GenServer.call(__MODULE__, {:write_transaction_chain, txs})
  end

  @impl true
  @spec list_transactions() :: list(Transaction.validated())
  def list_transactions() do
    GenServer.call(__MODULE__, :list_transactions)
  end
end
