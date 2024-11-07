defmodule Archethic.DB.EmbeddedImpl.ChainIndex do
  @moduledoc """
  Manage the indexing of the transaction chains for both file and memory storage
  """

  use GenServer
  @vsn 1

  alias Archethic.Crypto
  alias Archethic.DB
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias Archethic.TransactionChain.Transaction
  alias ArchethicCache.LRU

  @archethic_db_chain_stats :archethic_db_chain_stats
  @archethic_db_last_index :archethic_db_last_index
  @archethic_db_type_stats :archethic_db_type_stats
  @archetic_db_tx_index_cache :chain_index_cache

  # 100 Ko
  @batch_read_size 102_400

  require Logger

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(opts) do
    db_path = Keyword.fetch!(opts, :path)
    Logger.info("Index database at #{db_path}")

    setup_ets_table()

    fill_tables(db_path)

    {:ok, %{db_path: db_path}}
  end

  def setup_ets_table do
    :ets.new(@archethic_db_chain_stats, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@archethic_db_last_index, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@archethic_db_type_stats, [:set, :named_table, :public, read_concurrency: true])
  end

  defp fill_tables(db_path) do
    Task.async_stream(
      0..255,
      fn subset ->
        subset_summary_filename = index_summary_path(db_path, subset)
        scan_summary_table(subset_summary_filename)
      end,
      timeout: :infinity,
      max_concurrency: 16
    )
    |> Stream.run()

    fill_last_addresses(db_path)
    fill_type_stats(db_path)
  end

  defp scan_summary_table(filename) do
    filename
    |> File.stream!([], @batch_read_size)
    |> Enum.reduce(<<>>, fn content, acc ->
      do_scan_summary_table(<<acc::bitstring, content::bitstring>>)
    end)
  rescue
    _ -> :ok
  end

  defp do_scan_summary_table(<<>>), do: <<>>

  defp do_scan_summary_table(content) do
    with <<_current_curve_id::8, current_hash_type::8, rest::bitstring>> <- content,
         hash_size <- Crypto.hash_size(current_hash_type),
         <<_current_digest::binary-size(hash_size), genesis_curve_id::8, genesis_hash_type::8,
           rest::bitstring>> <- rest,
         hash_size <- Crypto.hash_size(genesis_hash_type),
         <<genesis_digest::binary-size(hash_size), size::32, _offset::32, rest::bitstring>> <-
           rest do
      genesis_address = <<genesis_curve_id::8, genesis_hash_type::8, genesis_digest::binary>>

      :ets.update_counter(
        @archethic_db_chain_stats,
        genesis_address,
        [
          {2, size},
          {3, 1}
        ],
        {genesis_address, 0, 0}
      )

      do_scan_summary_table(rest)
    else
      _rest -> content
    end
  end

  defp fill_last_addresses(db_path) do
    db_path
    |> list_genesis_addresses()
    |> Task.async_stream(
      fn genesis_address ->
        # Register last addresses of genesis address
        {last_address, timestamp} = get_last_chain_address(genesis_address, db_path)

        true =
          :ets.insert(
            @archethic_db_last_index,
            {genesis_address, last_address, DateTime.to_unix(timestamp, :millisecond)}
          )
      end,
      timeout: :infinity,
      max_concurrency: 16
    )
    |> Stream.run()
  end

  defp fill_type_stats(db_path) do
    Transaction.types()
    |> Task.async_stream(
      fn type ->
        case File.open(type_path(db_path, type), [:read, :binary]) do
          {:ok, fd} ->
            nb_txs = do_scan_types(fd)
            :ets.insert(@archethic_db_type_stats, {type, nb_txs})

          {:error, _} ->
            :ets.insert(@archethic_db_type_stats, {type, 0})
        end
      end,
      timeout: :infinity,
      max_concurrency: 16
    )
    |> Stream.run()
  end

  defp do_scan_types(fd, acc \\ 0) do
    with {:ok, <<_curve_id::8, hash_id::8>>} <- :file.read(fd, 2),
         hash_size <- Crypto.hash_size(hash_id),
         {:ok, _digest} <- :file.read(fd, hash_size) do
      do_scan_types(fd, acc + 1)
    else
      :eof ->
        :file.close(fd)
        acc
    end
  end

  @doc """
  Add transaction indexing inserting lookup back on file and on memory for fast lookup by genesis
  """
  @spec add_tx(binary(), binary(), non_neg_integer(), db_path :: String.t()) :: :ok
  def add_tx(
        tx_address = <<_::8, _::8, subset::8, _digest::binary>>,
        genesis_address,
        size,
        db_path
      ) do
    {last_offset, _nb_txs} = get_file_stats(genesis_address)

    # Write the transaction lookup in the subset index
    File.write!(
      index_summary_path(db_path, subset),
      <<tx_address::binary, genesis_address::binary, size::32, last_offset::32>>,
      [:binary, :append]
    )

    # pre-cache item (when node is not bootstrapping)
    # so they are already cached when we'll need them
    add_entry_to_cache(tx_address, %{
      size: size,
      offset: last_offset,
      genesis_address: genesis_address
    })

    :ets.update_counter(
      @archethic_db_chain_stats,
      genesis_address,
      [
        {2, size},
        {3, 1}
      ],
      {genesis_address, 0, 0}
    )

    :ok
  end

  @spec get_file_stats(binary()) ::
          {offset :: non_neg_integer(), nb_transactions :: non_neg_integer()}
  def get_file_stats(genesis_address) do
    case :ets.lookup(@archethic_db_chain_stats, genesis_address) do
      [{_, last_offset, nb_txs}] ->
        {last_offset, nb_txs}

      [] ->
        {0, 0}
    end
  end

  @doc """
  Return the size of a given transaction chain
  """
  @spec chain_size(binary(), String.t()) :: non_neg_integer()
  def chain_size(address, db_path) do
    # Get the genesis address for the given transaction's address
    {_, nb_txs} = get_genesis_address(address, db_path) |> get_file_stats()
    nb_txs
  end

  @doc """
  Determine if a transaction exists
  """
  @spec transaction_exists?(binary(), DB.storage_type(), String.t()) :: boolean()
  def transaction_exists?(address, storage_type \\ :chain, db_path)

  def transaction_exists?(address, storage_type, db_path) do
    case get_tx_entry(address, db_path) do
      {:ok, _} ->
        true

      {:error, :not_exists} ->
        if storage_type == :io,
          do: ChainWriter.io_path(db_path, address) |> File.exists?(),
          else: false
    end
  end

  @doc """
  Get transaction file entry
  """
  @spec get_tx_entry(binary(), String.t()) :: {:ok, map()} | {:error, :not_exists}
  def get_tx_entry(address, db_path) do
    case LRU.get(@archetic_db_tx_index_cache, address) do
      nil ->
        case search_tx_entry(address, db_path) do
          {:ok, entry} ->
            add_entry_to_cache(address, entry)
            {:ok, entry}

          {:error, :not_exists} ->
            {:error, :not_exists}
        end

      entry = %{} ->
        {:ok, entry}
    end
  end

  defp search_tx_entry(search_address = <<_::8, _::8, digest::binary>>, db_path) do
    <<subset::8, _::binary>> = digest

    db_path
    |> index_summary_path(subset)
    |> File.stream!([], @batch_read_size)
    |> Enum.reduce_while(<<>>, fn content, acc ->
      case do_search_tx_entry(<<acc::bitstring, content::bitstring>>, search_address) do
        rest when is_binary(rest) -> {:cont, rest}
        res when is_tuple(res) -> {:halt, res}
      end
    end)
    |> then(fn
      {genesis_address, size, offset} ->
        {:ok, %{genesis_address: genesis_address, size: size, offset: offset}}

      _ ->
        {:error, :not_exists}
    end)
  rescue
    _ -> {:error, :not_exists}
  end

  defp do_search_tx_entry(<<>>, _), do: <<>>

  defp do_search_tx_entry(content, search_address) do
    # We need to extract hash metadata information to know how many bytes to decode
    # as hashes can have different sizes based on the algorithm used
    with <<current_curve_id::8, current_hash_type::8, rest::bitstring>> <- content,
         hash_size <- Crypto.hash_size(current_hash_type),
         <<current_digest::binary-size(hash_size), genesis_curve_id::8, genesis_hash_type::8,
           rest::bitstring>> <- rest,
         hash_size <- Crypto.hash_size(genesis_hash_type),
         <<genesis_digest::binary-size(hash_size), size::32, offset::32, rest::bitstring>> <- rest do
      current_address = <<current_curve_id::8, current_hash_type::8, current_digest::binary>>

      # If it's the address we are looking for, we return the genesis address
      # and the chain file seeking information
      if current_address == search_address do
        genesis_address = <<genesis_curve_id::8, genesis_hash_type::8, genesis_digest::binary>>
        {genesis_address, size, offset}
      else
        do_search_tx_entry(rest, search_address)
      end
    else
      # This happens when the content is not a complete entry
      _rest -> content
    end
  end

  @doc """
  Stream all the transaction addresses for a given type
  """
  @spec get_addresses_by_type(Transaction.transaction_type(), String.t()) :: Enumerable.t()
  def get_addresses_by_type(type, db_path) do
    Stream.resource(
      fn -> File.open(type_path(db_path, type), [:read, :binary]) end,
      fn
        {:error, _} ->
          {:halt, nil}

        {:ok, fd} ->
          # We need to extract hash metadata information to know how many bytes to decode
          # as hashes can have different sizes based on the algorithm used
          with {:ok, <<curve_id::8, hash_id::8>>} <- :file.read(fd, 2),
               hash_size <- Crypto.hash_size(hash_id),
               {:ok, digest} <- :file.read(fd, hash_size) do
            address = <<curve_id::8, hash_id::8, digest::binary>>
            {[address], {:ok, fd}}
          else
            :eof ->
              {:halt, {:ok, fd}}
          end
      end,
      fn
        nil -> :ok
        {:ok, fd} -> :file.close(fd)
      end
    )
  end

  @doc """
  Stream all the transaction addresses from genesis_address-address.
  """
  @spec list_chain_addresses(binary(), String.t()) ::
          Enumerable.t() | list({binary(), DateTime.t()})
  def list_chain_addresses(address, db_path) when is_binary(address) do
    filepath = chain_addresses_path(db_path, address)

    Stream.resource(
      fn -> File.open(filepath, [:binary, :read]) end,
      fn
        {:error, _} ->
          {:halt, nil}

        {:ok, fd} ->
          with {:ok, <<timestamp::64>>} <- :file.read(fd, 8),
               {:ok, <<curve_id::8, hash_id::8>>} <- :file.read(fd, 2),
               hash_size <- Crypto.hash_size(hash_id),
               {:ok, hash} <- :file.read(fd, hash_size) do
            address = <<curve_id::8, hash_id::8, hash::binary>>
            # return tuple of address and timestamp
            {[{address, DateTime.from_unix!(timestamp, :millisecond)}], {:ok, fd}}
          else
            :eof ->
              :file.close(fd)
              {:halt, {:ok, fd}}
          end
      end,
      fn
        nil -> address
        {:ok, fd} -> :file.close(fd)
      end
    )
  end

  @doc """
  Stream all the public_keys from a genesis public key until a date
  """
  @spec list_chain_public_keys(binary(), DateTime.t(), String.t()) :: Enumerable.t()
  def list_chain_public_keys(public_key, until, db_path) when is_binary(public_key) do
    address = Crypto.derive_address(public_key)
    filepath = chain_keys_path(db_path, address)

    Stream.resource(
      fn -> File.open(filepath, [:binary, :read]) end,
      fn
        {:error, _} ->
          {:halt, nil}

        {:ok, fd} ->
          with {:ok, <<timestamp::64>>} <- :file.read(fd, 8),
               :lt <- DateTime.from_unix!(timestamp, :millisecond) |> DateTime.compare(until),
               {:ok, <<curve_id::8, origin_id::8>>} <- :file.read(fd, 2),
               key_size <- Crypto.key_size(curve_id),
               {:ok, key} <- :file.read(fd, key_size) do
            pub_key = <<curve_id::8, origin_id::8, key::binary>>
            # return tuple of address and timestamp
            {[{pub_key, DateTime.from_unix!(timestamp, :millisecond)}], {:ok, fd}}
          else
            e when e in [:eof, :eq, :gt] ->
              :file.close(fd)
              {:halt, {:ok, fd}}
          end
      end,
      fn
        nil -> public_key
        {:ok, fd} -> :file.close(fd)
      end
    )
  end

  @doc """
  Return the number of transactions for a given type
  """
  @spec count_transactions_by_type(Transaction.transaction_type()) :: non_neg_integer()
  def count_transactions_by_type(type) do
    case :ets.lookup(@archethic_db_type_stats, type) do
      [] ->
        0

      [{_, nb}] ->
        nb
    end
  end

  @doc """
  Insert transaction's address for a given transaction's type in its corresponding file
  """
  @spec add_tx_type(Transaction.transaction_type(), binary(), String.t()) ::
          :ok
  def add_tx_type(type, address, db_path) do
    File.write!(type_path(db_path, type), address, [:append, :binary])
    :ets.update_counter(@archethic_db_type_stats, type, {2, 1}, {type, 0})
    :ok
  end

  @doc """
  Set the last stored address
  """
  @spec set_last_chain_address_stored(
          genesis_address :: Crypto.prepended_hash(),
          tx_address :: Crypto.prepended_hash(),
          db_path :: binary()
        ) :: :ok
  def set_last_chain_address_stored(genesis_address, tx_address, db_path),
    do: last_chain_address_stored_path(db_path, genesis_address) |> File.write!(tx_address)

  @doc """
  Return the last address stored for a chain
  """
  @spec get_last_chain_address_stored(
          genesis_address :: Crypto.prepended_hash(),
          db_path :: binary()
        ) :: Crypto.prepended_hash() | nil
  def get_last_chain_address_stored(genesis_address, db_path) do
    filename = last_chain_address_stored_path(db_path, genesis_address)

    case File.read(filename) do
      {:ok, address} -> address
      _ -> nil
    end
  end

  @doc """
  Reference a new transaction address for the genesis address at the transaction time
  """
  @spec set_last_chain_address(binary(), binary(), DateTime.t(), String.t()) :: :ok
  def set_last_chain_address(
        genesis_address,
        new_address,
        datetime = %DateTime{},
        db_path
      ) do
    unix_time = DateTime.to_unix(datetime, :millisecond)

    encoded_data = <<unix_time::64, new_address::binary>>

    filename = chain_addresses_path(db_path, genesis_address)

    write_last_chain_transaction? =
      case :ets.lookup(@archethic_db_last_index, genesis_address) do
        [{_, ^new_address, _}] -> false
        [{_, _, chain_unix_time}] when unix_time < chain_unix_time -> false
        _ -> true
      end

    if write_last_chain_transaction? do
      :ok = File.write!(filename, encoded_data, [:binary, :append])
      true = :ets.insert(@archethic_db_last_index, {genesis_address, new_address, unix_time})
    end

    :ok
  end

  @doc """
  Return the last address of the chain
  """
  @spec get_last_chain_address(address :: binary(), db_path :: String.t()) ::
          {binary(), DateTime.t()}
  def get_last_chain_address(address, db_path) do
    # We try if the request address is the genesis address to fetch the in memory index
    case :ets.lookup(@archethic_db_last_index, address) do
      [] ->
        unix_time = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

        address
        |> get_genesis_address(db_path)
        |> get_last_address_until(unix_time, address, db_path)

      [{_, last_address, last_time}] ->
        {last_address, DateTime.from_unix!(last_time, :millisecond)}
    end
  end

  @doc """
  Return the last address of the chain before or equal to the given date
  """
  @spec get_last_chain_address(address :: binary(), until :: DateTime.t(), db_path :: String.t()) ::
          {last_addresss :: binary(), last_time :: DateTime.t()}
  def get_last_chain_address(address, datetime = %DateTime{}, db_path) do
    unix_time = DateTime.to_unix(datetime, :millisecond)
    # We try if the request address is the genesis address to fetch the in memory index
    case :ets.lookup(@archethic_db_last_index, address) do
      [] ->
        # We try with a transaction on a chain, to identity the genesis address

        address
        |> get_genesis_address(db_path)
        |> get_last_address_until(unix_time, address, db_path)

      [{_, _, last_time}] when last_time >= unix_time ->
        search_last_address_until(address, unix_time, db_path) ||
          {address, DateTime.from_unix!(0, :millisecond)}

      [{_, last_address, last_time}] ->
        {last_address, DateTime.from_unix!(last_time, :millisecond)}
    end
  end

  defp get_last_address_until(genesis_address, unix_time, default_address, db_path) do
    case :ets.lookup(@archethic_db_last_index, genesis_address) do
      [] ->
        search_last_address_until(genesis_address, unix_time, db_path) ||
          {default_address, DateTime.from_unix!(0, :millisecond)}

      [{_, _, last_time}] when last_time >= unix_time ->
        search_last_address_until(genesis_address, unix_time, db_path) ||
          {default_address, DateTime.from_unix!(0, :millisecond)}

      [{_, last_address, last_time}] ->
        {last_address, DateTime.from_unix!(last_time, :millisecond)}
    end
  end

  defp search_last_address_until(genesis_address, until, db_path) do
    filepath = chain_addresses_path(db_path, genesis_address)

    with {:ok, fd} <- File.open(filepath, [:binary, :read]),
         {address, timestamp} <- do_search_last_address_until(fd, until) do
      {address, DateTime.from_unix!(timestamp, :millisecond)}
    else
      nil ->
        nil

      {:error, _} ->
        nil
    end
  end

  defp do_search_last_address_until(fd, until, acc \\ nil) do
    with {:ok, <<timestamp::64>>} <- :file.read(fd, 8),
         {:ok, <<curve_id::8, hash_id::8>>} <- :file.read(fd, 2),
         hash_size <- Crypto.hash_size(hash_id),
         {:ok, hash} <- :file.read(fd, hash_size) do
      address = <<curve_id::8, hash_id::8, hash::binary>>

      if timestamp < until do
        do_search_last_address_until(fd, until, {address, timestamp})
      else
        :file.close(fd)
        acc
      end
    else
      :eof ->
        :file.close(fd)
        acc
    end
  end

  @doc """
  Return the genesis address of a chain

  If no genesis address is found, the given address is returned by default
  """
  @spec get_genesis_address(address :: Crypto.prepended_hash(), db_path :: String.t()) ::
          genesis_address :: Crypto.prepended_hash()
  def get_genesis_address(address, db_path) do
    with [] <- :ets.lookup(@archethic_db_chain_stats, address),
         {:error, :not_exists} <- get_tx_entry(address, db_path) do
      # If the transaction is not found (the transaction is not storred)
      # We may be aware if the genesis if the node storred a least one tranaction of this chain

      # :ets.fun2ms(fn {genesis, last_address, _} when last_address == address -> genesis end)
      match_pattern = [{{:"$1", :"$2", :_}, [{:==, :"$2", address}], [:"$1"]}]

      case :ets.select(@archethic_db_last_index, match_pattern, 1) do
        :"$end_of_table" -> address
        {[genesis_address], _} -> genesis_address
      end
    else
      [_] -> address
      {:ok, %{genesis_address: genesis_address}} -> genesis_address
    end
  end

  @doc """
  Return the genesis address of a chain
  """
  @spec find_genesis_address(address :: Crypto.prepended_hash(), db_path :: String.t()) ::
          {:ok, genesis_address :: Crypto.prepended_hash()} | {:error, :not_found}
  def find_genesis_address(address, db_path) do
    with [] <- :ets.lookup(@archethic_db_last_index, address),
         {:error, :not_exists} <- get_tx_entry(address, db_path) do
      # If the transaction is not found (the transaction is not storred)
      # We may be aware if the genesis if the node storred a least one tranaction of this chain

      # :ets.fun2ms(fn {genesis, last_address, _} when last_address == address -> genesis end)
      match_pattern = [{{:"$1", :"$2", :_}, [{:==, :"$2", address}], [:"$1"]}]

      case :ets.select(@archethic_db_last_index, match_pattern, 1) do
        :"$end_of_table" -> {:error, :not_found}
        {[genesis_address], _} -> {:ok, genesis_address}
      end
    else
      [_] -> {:ok, address}
      {:ok, %{genesis_address: genesis_address}} -> {:ok, genesis_address}
    end
  end

  @doc """
  Reference a new public key for the given genesis address
  """
  @spec set_public_key(binary(), Crypto.key(), DateTime.t(), String.t()) :: :ok
  def set_public_key(genesis_address, public_key, date = %DateTime{}, db_path) do
    unix_time = DateTime.to_unix(date, :millisecond)

    File.write!(
      chain_keys_path(db_path, genesis_address),
      <<unix_time::64, public_key::binary>>,
      [:binary, :append]
    )
  end

  @doc """
  Return the first public key of a chain by reading the genesis index file and capturing the first key

  If no key is found, the given public key is returned
  """
  @spec get_first_public_key(Crypto.key(), String.t()) :: Crypto.key()
  def get_first_public_key(public_key, db_path) do
    # We derive the previous address from the public key to get the genesis address
    # and its relative file
    address = Crypto.derive_address(public_key)
    genesis_address = get_genesis_address(address, db_path)
    filepath = chain_keys_path(db_path, genesis_address)

    case File.open(filepath, [:binary, :read]) do
      {:ok, fd} ->
        # We need to extract key metadata information to know how many bytes to decode
        # as keys can have different sizes based on the curve used
        with {:ok, <<_timestamp::64, curve_id::8, origin_id::8>>} <- :file.read(fd, 10),
             key_size <- Crypto.key_size(curve_id),
             {:ok, key} <- :file.read(fd, key_size) do
          # We then take the first public key registered
          :file.close(fd)
          <<curve_id::8, origin_id::8, key::binary>>
        else
          :eof ->
            :file.close(fd)
            public_key
        end

      {:error, _} ->
        public_key
    end
  end

  @doc """
  Stream all the file stats entries to indentify the addresses
  """
  @spec list_all_addresses(String.t()) :: Enumerable.t() | list(binary())
  def list_all_addresses(db_path) do
    db_path
    |> list_genesis_addresses()
    |> Stream.map(&scan_chain(&1, db_path))
    |> Stream.flat_map(& &1)
  end

  @doc """
  Stream all the genesis keys from the ETS file stats table
  """
  @spec list_genesis_addresses(String.t()) :: Enumerable.t()
  def list_genesis_addresses(db_path) do
    info = :ets.info(@archethic_db_chain_stats)

    # If the ets table is empty we list from the disk instead
    if Keyword.fetch!(info, :size) == 0 do
      db_path
      |> ChainWriter.base_chain_path()
      |> File.ls!()
      |> Enum.reject(fn file ->
        case Base.decode16(file) do
          {:ok, _} ->
            String.contains?(file, "-")

          _ ->
            true
        end
      end)
      |> Enum.map(&Base.decode16!/1)
    else
      Stream.resource(
        fn -> [] end,
        &stream_genesis_addresses/1,
        fn _ -> :ok end
      )
    end
  end

  defp stream_genesis_addresses(acc = []) do
    case :ets.first(@archethic_db_chain_stats) do
      :"$end_of_table" -> {:halt, acc}
      first_key -> {[first_key], first_key}
    end
  end

  defp stream_genesis_addresses(acc) do
    case :ets.next(@archethic_db_chain_stats, acc) do
      :"$end_of_table" -> {:halt, acc}
      next_key -> {[next_key], next_key}
    end
  end

  defp scan_chain(genesis_address, db_path) do
    filepath = chain_addresses_path(db_path, genesis_address)
    fd = File.open!(filepath, [:binary, :read])
    do_scan_chain(fd)
  end

  defp do_scan_chain(fd, acc \\ []) do
    with {:ok, <<_timestamp::64>>} <- :file.read(fd, 8),
         {:ok, <<curve_id::8, hash_id::8>>} <- :file.read(fd, 2),
         hash_size <- Crypto.hash_size(hash_id),
         {:ok, hash} <- :file.read(fd, hash_size) do
      address = <<curve_id::8, hash_id::8, hash::binary>>
      do_scan_chain(fd, [address | acc])
    else
      :eof ->
        :file.close(fd)
        acc
    end
  end

  defp add_entry_to_cache(address, entry) do
    if Archethic.up?() do
      LRU.put(@archetic_db_tx_index_cache, address, entry)
    end
  end

  defp index_summary_path(db_path, subset) do
    Path.join([ChainWriter.base_chain_path(db_path), "#{Base.encode16(<<subset>>)}-summary"])
  end

  defp chain_addresses_path(db_path, genesis_address) do
    Path.join([
      ChainWriter.base_chain_path(db_path),
      "#{Base.encode16(genesis_address)}-addresses"
    ])
  end

  defp last_chain_address_stored_path(db_path, genesis_address) do
    Path.join([
      ChainWriter.base_chain_path(db_path),
      "#{Base.encode16(genesis_address)}-last-stored-address"
    ])
  end

  defp type_path(db_path, type) do
    Path.join([ChainWriter.base_chain_path(db_path), Atom.to_string(type)])
  end

  defp chain_keys_path(db_path, genesis_address) do
    Path.join([ChainWriter.base_chain_path(db_path), "#{Base.encode16(genesis_address)}-keys"])
  end
end
