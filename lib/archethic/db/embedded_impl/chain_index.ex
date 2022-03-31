defmodule ArchEthic.DB.EmbeddedImpl.ChainIndex do
  use GenServer

  alias ArchEthic.Crypto

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:archethic_db_tx_index, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(:archethic_db_file_stats, [:set, :named_table, :public, read_concurrency: true])

    :ets.new(:archethic_db_last_index, [
      :ordered_set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    :ets.new(:archethic_db_first_index, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(:archethic_db_type_index, [:bag, :named_table, :public, read_concurrency: true])

    :ets.new(:archethic_db_public_key_index, [:set, :named_table, :public, read_concurrency: true])

    {:ok, %{}}
  end

  @doc """
  Add transaction file entry
  """
  @spec add_tx(binary(), binary(), binary(), non_neg_integer()) :: :ok
  def add_tx(tx_address, genesis_address, file, size) do
    {last_offset, _nb_txs} = get_file_stats(genesis_address)
    
    true =
      :ets.insert(
        :archethic_db_tx_index,
        {tx_address,
         %{file: file, size: size, offset: last_offset, genesis_address: genesis_address}}
      )

    :ets.update_counter(
      :archethic_db_file_stats,
      genesis_address,
      [
        {2, size},
        {3, 1}
      ],
      {genesis_address, 0, 0}
    )

    :ok
  end

  defp get_file_stats(genesis_address) do
    case :ets.lookup(:archethic_db_file_stats, genesis_address) do
      [{_, last_offset, nb_txs}] ->
        {last_offset, nb_txs}

      [] ->
        {0, 0}
    end
  end

  @doc """
  Flag the genesis address for this given transaction address and the address as last for the genesis
  """
  @spec add_first_and_last_reference(binary(), binary(), DateTime.t()) :: :ok
  def add_first_and_last_reference(tx_address, genesis_address, datetime = %DateTime{}) do
    unix_time = DateTime.to_unix(datetime)
    true = :ets.insert(:archethic_db_first_index, {tx_address, genesis_address})

    true =
      :ets.insert(:archethic_db_last_index, {{genesis_address, unix_time}, tx_address})

    :ok
  end

  @doc """
  Return the size of a given transaction chain
  """
  @spec chain_size(binary()) :: non_neg_integer()
  def chain_size(address) do
    # Get the genesis address for the given transaction's address
    case get_tx_entry(address) do
      {:ok, %{genesis_address: genesis_address}} ->
        # Get the chain file stats including the nb of transactions written
        {_, nb_txs} = get_file_stats(genesis_address)
        nb_txs

      {:error, :not_exists} ->
        0
    end
  end

  @doc """
  Determine if a transaction exists
  """
  @spec transaction_exists?(binary()) :: boolean()
  def transaction_exists?(address) do
    :ets.member(:archethic_db_tx_index, address)
  end

  @doc """
  Get transaction file entry
  """
  @spec get_tx_entry(binary()) :: {:ok, map()} | {:error, :not_exists}
  def get_tx_entry(address) do
    case :ets.lookup(:archethic_db_tx_index, address) do
      [] ->
        {:error, :not_exists}

      [{_address, entry}] ->
        {:ok, entry}
    end
  end

  @doc """
  List all the transaction addresses for a given type
  """
  @spec get_addresses_by_type(Transaction.transaction_type()) :: list(binary())
  def get_addresses_by_type(type) do
    Enum.map(:ets.lookup(:archethic_db_type_index, type), fn {_, type} ->
      type
    end)
  end

  @doc """
  Insert entry to add transaction's address for a given transaction's type
  """
  @spec add_tx_type(Transaction.transaction_type(), binary()) :: :ok
  def add_tx_type(type, address) do
    true = :ets.insert(:archethic_db_type_index, {type, address})
    :ok
  end

  @doc """
  Insert entry to define the last chain address of an address, sorted by date of the transaction
  """
  @spec set_last_chain_address(binary(), binary(), DateTime.t()) :: :ok
  def set_last_chain_address(previous_address, new_address, datetime = %DateTime{}) do
    unix_time = DateTime.to_unix(datetime)

    case get_tx_entry(previous_address) do
      {:ok, %{genesis_address: genesis_address}} ->
        true = :ets.insert(:archethic_db_last_index, {{genesis_address, unix_time}, new_address})
        :ok

      {:error, :not_exists} ->
        :ok
    end
  end

  @doc """
  Return the last address of the chain before or equal to the given date
  """
  @spec get_last_chain_address(binary(), DateTime.t()) :: binary()
  def get_last_chain_address(address, datetime = %DateTime{}) do
    unix_time = DateTime.to_unix(datetime)

    # We get the genesis address of this given transaction address
    case get_tx_entry(address) do
      {:ok, %{genesis_address: genesis_address}} ->
        case lookup_previous_address(genesis_address, unix_time) do
          nil ->
            address
          last_address ->
            last_address
        end
      {:error, :not_exists} ->

        # We try to search with given address as genesis address
        case lookup_previous_address(address, unix_time) do
          nil ->
            address
          last_address ->
            last_address
        end
    end
  end

  defp lookup_previous_address(genesis_address, unix_time) do
        # We first check if there is some address indexed for the given date
        case :ets.lookup(:archethic_db_last_index, {genesis_address, unix_time}) do
          [{_, last_address}] ->
            last_address

          [] ->
            # Then we get the latest before this date
            lookup =
              case :ets.prev(:archethic_db_last_index, {genesis_address, unix_time}) do
                :"$end_of_table" ->
                  :ets.lookup(:archethic_db_last_index, {genesis_address, unix_time})

                key ->
                  :ets.lookup(:archethic_db_last_index, key)
                
              end

            case lookup do
              [] ->
                # If finaly we got nothing, we return the given address to search
                nil

              [{_, last_address}] ->
                last_address
            end
        end

  end

  @doc """
  Return the first address of a chain

  If not address is found, the given address is returned
  """
  @spec get_first_chain_address(binary()) :: binary()
  def get_first_chain_address(address) do
    case :ets.lookup(:archethic_db_first_index, address) do
      [] ->
        address

      [{_, first_address}] ->
        first_address
    end
  end

  @doc """
  Insert entry for lookup based on the previous public key and transaction address
  """
  @spec set_public_key_lookup(binary(), Crypto.key()) :: :ok
  def set_public_key_lookup(tx_address, previous_public_key) do
    true = :ets.insert(:archethic_db_public_key_index, {{:addr, tx_address}, previous_public_key})
    previous_address = Crypto.derive_address(previous_public_key)

    # We check if there a previous address registered in this chain and get its public key
    case :ets.lookup(:archethic_db_public_key_index, {:addr, previous_address}) do
      [] ->
        true =
          :ets.insert(
            :archethic_db_public_key_index,
            {{:key, previous_public_key}, previous_public_key}
          )

      [{_, older_public_key}] ->
        # We fetch the first public key registered for this previous address
        [{_, first_public_key}] =
          :ets.lookup(:archethic_db_public_key_index, {:key, older_public_key})

        # We insert the for the given public key the first public key
        true =
          :ets.insert(
            :archethic_db_public_key_index,
            {{:key, previous_public_key}, first_public_key}
          )
    end

    :ok
  end

  @doc """
  Return the first public key of a chain

  If no key is found, the given public key is returned
  """
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  def get_first_public_key(public_key) do
    case :ets.lookup(:archethic_db_public_key_index, {:key, public_key}) do
      [] ->
        public_key

      [{_, public_key}] ->
        public_key
    end
  end

  @spec list_all_addresses() :: list(binary())
  def list_all_addresses do
    Stream.resource(
      fn -> [] end,
      fn acc ->
        case acc do
          [] ->
            case :ets.first(:archethic_db_tx_index) do
              :"$end_of_table" -> {:halt, acc}
              first_key -> {[first_key], first_key}
            end

          acc ->
            case :ets.next(:archethic_db_tx_index, acc) do
              :"$end_of_table" -> {:halt, acc}
              next_key -> {[next_key], next_key}
            end
        end
      end,
      fn _ -> :ok end
    )
  end
end
