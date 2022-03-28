defmodule ArchEthic.DB.EmbeddedImpl.Writer do
  @moduledoc false

  use GenServer

  alias ArchEthic.DB.EmbeddedImpl.Encoding
  alias ArchEthic.DB.EmbeddedImpl.Index

  alias ArchEthic.TransactionChain.Transaction

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec append_transaction(binary(), Transaction.t()) :: :ok
  def append_transaction(genesis_address, tx = %Transaction{}) do
    GenServer.call(__MODULE__, {:append_tx, genesis_address, tx})
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
    unless Index.transaction_exists?(tx_address) do
      filename = Path.join([db_path, "chains", Base.encode16(genesis_address)])

      data = Encoding.encode(tx)

      File.write(
        filename,
        data,
        [:append, :binary]
      )

      Index.add_tx(tx_address, genesis_address, filename, byte_size(data))
    end

    {:reply, :ok, state}
  end
end
