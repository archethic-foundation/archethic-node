defmodule UnirisChain.DefaultImpl.Store.FileImpl do
  @moduledoc false
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.Data.Ledger.UCO
  alias UnirisChain.Transaction.Data.Ledger.Transfer
  alias UnirisChain.TransactionSupervisor

  use GenServer

  @behaviour UnirisChain.DefaultImpl.Store.Impl

  @transactions_dir Application.app_dir(:uniris_chain, "priv/db/transactions")
  @indexes_dir Application.app_dir(:uniris_chain, "priv/db/indexes")

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    File.mkdir_p!(@transactions_dir)
    File.mkdir_p!(@indexes_dir)
    {:ok, %{}, {:continue, :load_transactions}}
  end

  @impl true
  def handle_continue(:load_transactions, state) do
    case File.ls(@transactions_dir) do
      {:ok, files} ->
        Enum.map(files, fn file ->
          tx =
            File.read!(@transactions_dir <> "/" <> file)
            |> :erlang.binary_to_term()

          DynamicSupervisor.start_child(TransactionSupervisor, {Transaction, tx})
        end)

        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:get_transaction, address}, _, state) do
    try do
      {:reply, read_transaction!(address), state}
    rescue
      _ ->
        {:reply, nil, state}
    end
  end

  def handle_call(
        {:get_transaction_chain, address},
        _from,
        state
      ) do
    with {:ok, data} <- File.read("#{@indexes_dir}/chain_#{Base.encode16(address)}"),
         addresses when is_list(addresses) <- :erlang.binary_to_term(data) do
      transactions = Enum.map(addresses, &read_transaction!/1)
      {:reply, transactions, state}
    else
      {:error, _} ->
        {:reply, [], state}
    end
  end

  def handle_call(
        {:get_unspent_output_transactions, address},
        _from,
        state
      ) do
    try do
      txs =
        "#{@indexes_dir}/utxo_#{Base.encode16(address)}"
        |> File.read!()
        |> :erlang.binary_to_term()
        |> Enum.map(&read_transaction!/1)

      {:reply, txs, state}
    rescue
      _ ->
        {:reply, [], state}
    end
  end

  def handle_call(
        :get_last_node_shared_secrets_transaction,
        _from,
        state
      ) do
    case File.read("#{@indexes_dir}/node_shared_secrets_tx") do
      {:ok, data} ->
        tx_address = :erlang.binary_to_term(data)

        try do
          {:reply, read_transaction!(tx_address), state}
        rescue
          _ ->
            {:reply, nil, state}
        end

      _ ->
        {:reply, nil, state}
    end
  end

  def handle_call(:list_transactions, _from, state) do
    case File.ls(@transactions_dir) do
      {:ok, files} ->
        txs =
          Enum.map(files, fn file ->
            File.read!(@transactions_dir <> "/" <> file)
            |> :erlang.binary_to_term()
          end)

        {:reply, txs, state}

      _ ->
        {:reply, [], state}
    end
  end

  def handle_call(:node_transactions, _from, state) do
    case File.read("#{@indexes_dir}/node_transactions") do
      {:ok, data} ->
        nodes =
          :erlang.binary_to_term(data)
          |> Enum.map(&read_transaction!/1)

        {:reply, nodes, state}

      _ ->
        {:reply, [], state}
    end
  end

  @impl true
  def handle_cast(
        {:store_transaction, tx = %Transaction{}},
        state
      ) do
    File.write!(
      "#{@transactions_dir}/#{Base.encode16(tx.address)}",
      :erlang.term_to_binary(tx),
      [:write]
    )

    build_indexes(tx)

    {:noreply, state}
  end

  def handle_cast(
        {:store_transaction_chain, txs},
        state
      ) do
    Enum.each(txs, fn tx ->
      File.write!(
        "#{@transactions_dir}/#{Base.encode16(tx.address)}",
        :erlang.term_to_binary(tx),
        [:write]
      )
    end)

    File.write!(
      "#{@indexes_dir}/chain_#{Base.encode16(List.first(txs).address)}",
      :erlang.term_to_binary(Enum.map(txs, & &1.address)),
      [:write]
    )

    build_indexes(List.first(txs))

    {:noreply, state}
  end

  defp build_indexes(tx = %Transaction{address: tx_address, type: type}) do
    build_unspent_outputs_indexes(tx)

    case type do
      :node_shared_secrets ->
        File.write("#{@indexes_dir}/node_shared_secrets_tx", :erlang.term_to_binary(tx_address), [
          :write
        ])

      :node ->
        case File.read("#{@indexes_dir}/node_transactions") do
          {:ok, data} ->
            node_txs =
              data
              |> :erlang.binary_to_term()
              |> Kernel.++([tx.address])
              |> :erlang.term_to_binary()

            File.write("#{@indexes_dir}/node_transactions", node_txs, [:write])

          _ ->
            File.write(
              "#{@indexes_dir}/node_transactions",
              :erlang.term_to_binary([tx.address]),
              [:write]
            )
        end

      _ ->
        :ok
    end
  end

  defp build_unspent_outputs_indexes(%Transaction{address: tx_address, data: %{ledger: ledger}}) do
    case ledger do
      %{uco: %UCO{transfers: uco_transfers}} ->
        Enum.reduce(uco_transfers, %{}, fn %Transfer{to: recipient}, acc ->
          Map.update(acc, recipient, [tx_address], &(&1 ++ [tx_address]))
        end)
        |> Enum.each(fn {recipient, unspent_outputs} ->
          utxo_file = "#{@indexes_dir}/utxo_#{Base.encode16(recipient)}"

          case File.read(utxo_file) do
            {:ok, data} ->
              utxos = :erlang.binary_to_term(data) ++ unspent_outputs
              File.write!(utxo_file, :erlang.term_to_binary(utxos))

            _ ->
              File.write!(utxo_file, :erlang.term_to_binary(unspent_outputs), [:write])
          end
        end)

      _ ->
        :ok
    end
  end

  defp read_transaction!(address) do
    "#{@transactions_dir}/#{Base.encode16(address)}"
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
  @spec store_transaction(Transaction.validated()) :: :ok
  def store_transaction(tx = %Transaction{}) do
    GenServer.cast(__MODULE__, {:store_transaction, tx})
  end

  @impl true
  @spec store_transaction_chain(list(Transaction.validated())) :: :ok
  def store_transaction_chain(txs) when is_list(txs) do
    GenServer.cast(__MODULE__, {:store_transaction_chain, txs})
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
end
