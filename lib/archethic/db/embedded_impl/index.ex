defmodule ArchEthic.DB.EmbeddedImpl.Index do
  use GenServer

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:archethic_db_tx_index, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(:archethic_db_file_stats, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  def add_tx(tx_address, genesis_address, file, size) do
    last_offset = get_last_offset(genesis_address)

    true =
      :ets.insert(
        :archethic_db_tx_index,
        {tx_address, file, size, last_offset, genesis_address}
      )

    true = :ets.insert(:archethic_db_file_stats, {genesis_address, last_offset + size})
    :ok
  end

  def transaction_exists?(address) do
    case :ets.lookup(:archethic_db_tx_index, address) do
      [] ->
        false

      _ ->
        true
    end
  end

  def get_tx_entry(address) do
    case :ets.lookup(:archethic_db_tx_index, address) do
      [] ->
        {:error, :not_exists}

      [{address, file, size, offset, genesis_address}] ->
        {:ok,
         %{
           transaction_address: address,
           file: file,
           size: size,
           offset: offset,
           genesis_address: genesis_address
         }}
    end
  end

  def get_last_offset(genesis_address) do
    case :ets.lookup(:archethic_db_file_stats, genesis_address) do
      [] ->
        0

      [{_, offset}] ->
        offset
    end
  end
end
