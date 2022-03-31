defmodule ArchEthic.DB.EmbeddedImpl.ChainWriter do
  @moduledoc false

  use GenServer

  alias ArchEthic.DB.EmbeddedImpl.Encoding
  alias ArchEthic.DB.EmbeddedImpl.Index

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc """
  Append a transaction to a file for the given genesis address
  """
  @spec append_transaction(binary(), Transaction.t()) ::
          :ok | {:error, :transaction_already_exists}
  def append_transaction(genesis_address, tx = %Transaction{address: tx_address}) do
    if Index.transaction_exists?(tx_address) do
      {:error, :transaction_already_exists}
    else
      :ok = GenServer.call(__MODULE__, {:append_tx, genesis_address, tx})
    end
  end

  @doc """
  Return the database path
  """
  @spec get_db_path() :: String.t()
  def get_db_path do
    [{_, path}] = :ets.lookup(:archethic_db_info, :path)
    path
  end

  def init(arg) do
    db_path = Keyword.get(arg, :path)
    setup_folders(db_path)

    :ets.new(:archethic_db_info, [:public, :named_table])
    :ets.insert(:archethic_db_info, {:path, db_path})

    {:ok, %{db_path: db_path}}
  end

  defp setup_folders(path) do
    File.mkdir_p!(Path.join(path, "chains"))
  end

  def handle_call(
        {:append_tx, genesis_address, tx},
        _from,
        state = %{db_path: db_path}
      ) do
    filename = Path.join([db_path, "chains", Base.encode16(genesis_address)])

    data = Encoding.encode(tx)

    File.write!(
      filename,
      data,
      [:append, :binary]
    )

    index_transaction(tx, filename, genesis_address, byte_size(data))

    {:reply, :ok, state}
  end

  def handle_cast({:register_tps, date, tps, nb_transactions}, state = %{db_path: db_path}) do
    filename = Path.join(db_path, "stats")

    File.write!(
      filename,
      <<1::8, DateTime.to_unix(date)::32, tps::float-64, nb_transactions::32>>
    )

    {:noreply, state}
  end

  defp index_transaction(
         tx = %Transaction{
           address: tx_address,
           type: tx_type,
           previous_public_key: previous_public_key,
           validation_stamp: %ValidationStamp{timestamp: timestamp}
         },
         filename,
         genesis_address,
         encoded_size
       ) do
    Index.add_tx(tx_address, genesis_address, filename, encoded_size)
    Index.add_tx_type(tx_type, tx_address)

    previous_address = Transaction.previous_address(tx)

    previous_chain_addresses = Index.get_chain_addresses(previous_address)

    Index.set_chain_addresses(tx_address, [tx_address | previous_chain_addresses])

    # For all the chain transaction addresses, set the new transaction as the latest one
    Enum.each(
      [tx_address | previous_chain_addresses],
      &Index.set_last_chain_address(&1, tx_address, timestamp)
    )

    # Create a lookup of the address and the previous public key
    Index.set_public_key_lookup(tx_address, previous_public_key)
  end
end
