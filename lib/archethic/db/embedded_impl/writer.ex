defmodule ArchEthic.DB.EmbeddedImpl.Writer do
  @moduledoc false

  use GenServer

  alias ArchEthic.DB.EmbeddedImpl.Encoding
  alias ArchEthic.DB.EmbeddedImpl.Index

  alias ArchEthic.TransactionChain.Transaction

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

  def init(arg) do
    db_path = Keyword.get(arg, :path)
    setup_folders(db_path)
    {:ok, %{db_path: db_path}}
  end

  defp setup_folders(path) do
    File.mkdir_p!(path)
    File.mkdir_p!(Path.join(path, "chains"))
  end

  def handle_call(
        {:append_tx, genesis_address, tx = %Transaction{address: tx_address}},
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

    Index.add_tx(tx_address, genesis_address, filename, byte_size(data))

    chain_addresses = Index.get_chain_addresses(Transaction.previous_address(tx))

    Index.set_chain_addresses(tx_address, [tx_address | chain_addresses])
    {:reply, :ok, state}
  end
end
