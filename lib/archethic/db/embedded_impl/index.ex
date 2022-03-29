defmodule ArchEthic.DB.EmbeddedImpl.Index do
  use GenServer

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:archethic_db_tx_index, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(:archethic_db_file_stats, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(:archethic_db_chain_index, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  Add transaction file entry
  """
  @spec add_tx(binary(), binary(), binary(), non_neg_integer()) :: :ok
  def add_tx(tx_address, genesis_address, file, size) do
    last_offset = get_last_offset(genesis_address)

    true =
      :ets.insert(
        :archethic_db_tx_index,
        {tx_address,
         %{file: file, size: size, offset: last_offset, genesis_address: genesis_address}}
      )

    true = :ets.insert(:archethic_db_file_stats, {genesis_address, last_offset + size})
    :ok
  end

  defp get_last_offset(genesis_address) do
    case :ets.lookup(:archethic_db_file_stats, genesis_address) do
      [] ->
        0

      [{_, offset}] ->
        offset
    end
  end

  @doc """
  Determine if a transaction exists
  """
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) do
    case :ets.lookup(:archethic_db_tx_index, address) do
      [] ->
        false

      _ ->
        true
    end
  end

  @doc """
  Get transaction file entry
  """
  def get_tx_entry(address) do
    case :ets.lookup(:archethic_db_tx_index, address) do
      [] ->
        {:error, :not_exists}

      [{_address, entry}] ->
        {:ok, entry}
    end
  end

  @doc """
  List transaction addresses for a given chain
  """
  @spec get_chain_addresses(binary()) :: list(binary())
  def get_chain_addresses(address) do
    case :ets.lookup(:archethic_db_chain_index, address) do
      [] ->
        []

      [{_, addresses}] ->
        addresses
    end
  end

  @spec set_chain_addresses(binary(), list(binary())) :: :ok
  def set_chain_addresses(_chain_address, []), do: :ok

  def set_chain_addresses(chain_address, transaction_addresses) do
    true = :ets.insert(:archethic_db_chain_index, {chain_address, transaction_addresses})
    :ok
  end
end
