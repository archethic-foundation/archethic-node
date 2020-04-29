defmodule UnirisCore.Storage.FileBackend do
  @moduledoc false

  alias UnirisCore.Crypto
  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer

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
        Application.get_env(:uniris_core, UnirisCore.Crypto)[:seed]
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

  def handle_call(
        {:get_unspent_output_transactions, address},
        _from,
        state = %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}
      ) do
    {:reply, do_get_unspent_outputs_transactions(transactions_dir, indexes_dir, address), state}
  end

  def handle_call(
        :get_last_node_shared_secrets_transaction,
        _from,
        state = %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}
      ) do
    {:reply, do_get_last_node_shared_key_transaction(transactions_dir, indexes_dir), state}
  end

  def handle_call(:list_transactions, _from, state = %{transactions_dir: dir}) do
    {:reply, do_list_transactions(dir), state}
  end

  def handle_call(
        :node_transactions,
        _from,
        state = %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}
      ) do
    {:reply, do_list_node_transactions(transactions_dir, indexes_dir), state}
  end

  def handle_call(
        :list_unspent_outputs,
        _,
        state = %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}
      ) do
    {:reply, do_list_unspent_outputs(transactions_dir, indexes_dir), state}
  end

  def handle_call(
        :list_origin_shared_secrets,
        _,
        state = %{transactions_dir: transactions_dir, indexes_dir: indexes_dir}
      ) do
    {:reply, do_list_origin_shared_secrets(transactions_dir, indexes_dir), state}
  end

  @impl true
  def handle_call(
        {:write_transaction, tx = %Transaction{}},
        _,
        state = %{transactions_dir: dir, indexes_dir: indexes_dir}
      ) do
    File.write!(
      Path.join(dir, Base.encode16(tx.address)),
      :erlang.term_to_binary(tx),
      [:write]
    )

    build_indexes(indexes_dir, tx)

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

    build_indexes(indexes_dir, List.first(txs))

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

  defp do_get_last_node_shared_key_transaction(transactions_dir, indexes_dir) do
    case File.read(Path.join(indexes_dir, "last_node_shared_secrets_tx")) do
      {:ok, data} ->
        try do
          read_transaction!(transactions_dir, data)
        rescue
          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp do_list_node_transactions(transactions_dir, indexes_dir) do
    case File.read(Path.join(indexes_dir, "node_transactions")) do
      {:ok, data} ->
        data
        |> String.split("\n")
        |> Enum.map(&read_transaction!(transactions_dir, &1))

      _ ->
        []
    end
  end

  defp do_get_unspent_outputs_transactions(transactions_dir, indexes_dir, address) do
    try do
      txs =
        Path.join(indexes_dir, "utxo_#{Base.encode16(address)}")
        |> File.read!()
        |> String.split("\n")
        |> Enum.map(&read_transaction!(transactions_dir, &1))

      txs
    rescue
      _ ->
        []
    end
  end

  defp do_list_unspent_outputs(transactions_dir, indexes_dir) do
    case File.ls(indexes_dir) do
      {:ok, files} ->
        Enum.filter(files, fn file -> String.contains?(file, "uxto_") end)
        |> Enum.map(fn file ->
          File.read!(file)
        end)
        |> Enum.flat_map(& &1)
        |> Enum.map(&read_transaction!(transactions_dir, &1))

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

  defp do_list_origin_shared_secrets(indexes_dir, transactions_dir) do
    case File.ls(indexes_dir) do
      {:ok, files} ->
        Enum.filter(files, fn file -> String.contains?(file, "origin_shared_secrets") end)
        |> Enum.map(fn file ->
          file
          |> File.read!()
        end)
        |> Enum.flat_map(& &1)
        |> Enum.map(&read_transaction!(transactions_dir, &1))

      _ ->
        []
    end
  end

  defp build_indexes(indexes_dir, tx = %Transaction{}) do
    build_type_indexes(indexes_dir, tx)
    build_unspent_outputs_indexes(indexes_dir, tx)
  end

  defp build_type_indexes(indexes_dir, %Transaction{type: :node, address: tx_address}) do
    node_transactions_file = Path.join(indexes_dir, "node_transactions")

    case File.read(node_transactions_file) do
      {:ok, data} ->
        data = data <> "\n" <> Base.encode16(tx_address)
        File.write(node_transactions_file, data, [:write])

      _ ->
        File.write(
          node_transactions_file,
          Base.encode16(tx_address),
          [:write]
        )
    end
  end

  defp build_type_indexes(indexes_dir, %Transaction{
         type: :node_shared_secrets,
         address: tx_address
       }) do
    File.write(
      Path.join(indexes_dir, "last_node_shared_secrets_tx"),
      Base.encode16(tx_address),
      [
        :write
      ]
    )
  end

  defp build_type_indexes(_, %Transaction{}) do
  end

  defp build_unspent_outputs_indexes(indexes_dir, %Transaction{
         address: tx_address,
         data: %{ledger: ledger}
       }) do
    case ledger do
      %{uco: %UCOLedger{transfers: uco_transfers}} ->
        Enum.reduce(uco_transfers, %{}, fn %Transfer{to: recipient}, acc ->
          Map.update(acc, recipient, [tx_address], &(&1 ++ [tx_address]))
        end)
        |> Enum.each(fn {recipient, unspent_outputs} ->
          utxo_file = Path.join(indexes_dir, "utxo_#{Base.encode16(recipient)}")

          case File.read(utxo_file) do
            {:ok, data} ->
              utxos = data <> "\n" <> Base.encode16(tx_address)
              File.write!(utxo_file, :erlang.term_to_binary(utxos))

            _ ->
              data =
                unspent_outputs
                |> Enum.reduce([], fn address, acc ->
                  acc ++ [Base.encode16(address)]
                end)
                |> Enum.join("\n")

              File.write!(utxo_file, data, [:write])
          end
        end)

      _ ->
        :ok
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

  @spec node_transactions() :: list(Transaction.validated())
  @impl true
  def node_transactions() do
    GenServer.call(__MODULE__, :node_transactions)
  end

  @impl true
  @spec unspent_outputs_transactions() :: list(Transaction.validated())
  def unspent_outputs_transactions() do
    GenServer.call(__MODULE__, :list_unspent_outputs)
  end

  @impl true
  @spec origin_shared_secrets_transactions() :: list(Transaction.validated())
  def origin_shared_secrets_transactions() do
    GenServer.call(__MODULE__, :list_origin_shared_secrets)
  end
end
