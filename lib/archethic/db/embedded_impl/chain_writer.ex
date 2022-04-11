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

    {:ok, %{db_path: db_path}}
  end

  defp setup_folders(path) do
    path
    |> base_path()
    |> File.mkdir_p!()
  end

  def handle_call(
        {:append_tx, genesis_address, tx},
        _from,
        state = %{db_path: db_path}
      ) do
    filename = chain_path(db_path, genesis_address)

    data = Encoding.encode(tx)

    File.write!(
      filename,
      data,
      [:append, :binary]
    )

    index_transaction(tx, genesis_address, byte_size(data), db_path)

    {:reply, :ok, state}
  end

  defp index_transaction(
         tx = %Transaction{
           address: tx_address,
           type: tx_type,
           previous_public_key: previous_public_key,
           validation_stamp: %ValidationStamp{timestamp: timestamp}
         },
         genesis_address,
         encoded_size,
         db_path
       ) do
    previous_address = Transaction.previous_address(tx)

    ChainIndex.add_tx(tx_address, genesis_address, encoded_size, db_path)
    ChainIndex.add_tx_type(tx_type, tx_address, db_path)
    ChainIndex.set_last_chain_address(previous_address, tx_address, timestamp, db_path)
    ChainIndex.set_public_key(genesis_address, previous_public_key, timestamp, db_path)
  end

  @doc """
  Return the path of the chain storage location
  """
  @spec chain_path(String.t(), binary()) :: String.t()
  def chain_path(db_path, genesis_address)
      when is_binary(genesis_address) and is_binary(db_path) do
    Path.join([base_path(db_path), Base.encode16(genesis_address)])
  end

  @doc """
  Return the chain base path
  """
  @spec base_path(String.t()) :: String.t()
  def base_path(db_path) do
    Path.join([db_path, "chains"])
  end
end
