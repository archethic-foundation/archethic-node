defmodule ArchEthic.DB.EmbeddedImpl.ChainWriter do
  @moduledoc false

  use GenServer

  alias ArchEthic.DB.EmbeddedImpl.Encoding
  alias ArchEthic.DB.EmbeddedImpl.ChainIndex

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc """
  Append a transaction to a file for the given genesis address
  """
  @spec append_transaction(binary(), Transaction.t()) :: :ok
  def append_transaction(genesis_address, tx = %Transaction{}) do
    GenServer.call(__MODULE__, {:append_tx, genesis_address, tx})
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

  defp index_transaction(
         %Transaction{
           address: tx_address,
           type: tx_type,
           previous_public_key: previous_public_key,
           validation_stamp: %ValidationStamp{timestamp: timestamp}
         },
         filename,
         genesis_address,
         encoded_size
       ) do
    ChainIndex.add_tx(tx_address, genesis_address, filename, encoded_size)
    ChainIndex.add_tx_type(tx_type, tx_address)
    ChainIndex.set_public_key_lookup(tx_address, previous_public_key)
    ChainIndex.add_first_and_last_reference(tx_address, genesis_address, timestamp)
  end
end
