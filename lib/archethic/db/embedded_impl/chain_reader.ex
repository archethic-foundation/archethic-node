defmodule Archethic.DB.EmbeddedImpl.ChainReader do
  @moduledoc false

  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias Archethic.DB.EmbeddedImpl.Encoding

  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils

  @page_size 10

  @spec get_transaction(address :: binary(), fields :: list(), db_path :: String.t()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_transaction(address, fields, db_path) do
    start = System.monotonic_time()

    case ChainIndex.get_tx_entry(address, db_path) do
      {:error, :not_exists} ->
        {:error, :transaction_not_exists}

      {:ok, %{offset: offset, genesis_address: genesis_address}} ->
        filepath = ChainWriter.chain_path(db_path, genesis_address)

        # Open the file as the position from the transaction in the chain file
        fd = File.open!(filepath, [:binary, :read])
        :file.position(fd, offset)

        {:ok, <<size::32, version::32>>} = :file.pread(fd, offset, 8)
        column_names = fields_to_column_names(fields)

        # Ensure the validation stamp's protocol version is retrieved if we fetch validation stamp fields
        has_validation_stamp_fields? =
          Enum.any?(column_names, &String.starts_with?(&1, "validation_stamp."))

        has_validation_stamp_protocol_field? =
          Enum.any?(column_names, &(&1 == "validation_stamp.protocol_version"))

        column_names =
          if has_validation_stamp_fields? and !has_validation_stamp_protocol_field? do
            ["validation_stamp.protocol_version" | column_names]
          else
            column_names
          end

        # Read the transaction and extract requested columns from the fields arg
        tx =
          fd
          |> read_transaction(column_names, size, 0)
          |> Enum.into(%{})
          |> decode_transaction_columns(version)

        :file.close(fd)

        :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
          query: "get_transaction"
        })

        {:ok, tx}
    end
  end

  @doc """
  Get a beacon summary from a given summary address
  """
  @spec get_beacon_summary(summary_address :: binary(), db_path :: String.t()) ::
          {:ok, Summary.t()} | {:error, :summary_not_exists}
  def get_beacon_summary(summary_address, db_path) do
    start = System.monotonic_time()
    filepath = ChainWriter.beacon_path(db_path, summary_address)

    with true <- File.exists?(filepath),
         {:ok, data} <- File.read(filepath),
         {summary, _} <- Summary.deserialize(data) do
      :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
        query: "get_beacon_summary"
      })

      {:ok, summary}
    else
      _ ->
        {:error, :summary_not_exists}
    end
  end

  @doc """
  Get a beacon summaries aggregate from a given date
  """
  @spec get_beacon_summaries_aggregate(summary_time :: DateTime.t(), db_path :: String.t()) ::
          {:ok, SummaryAggregate.t()} | {:error, :not_exists}
  def get_beacon_summaries_aggregate(date = %DateTime{}, db_path) when is_binary(db_path) do
    start = System.monotonic_time()
    filepath = ChainWriter.beacon_aggregate_path(db_path, date)

    with true <- File.exists?(filepath),
         {:ok, data} <- File.read(filepath),
         {aggregate, _} <- SummaryAggregate.deserialize(data) do
      :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
        query: "get_beacon_summaries_aggregate"
      })

      {:ok, aggregate}
    else
      _ ->
        {:error, :not_exists}
    end
  end

  @spec get_transaction_chain(
          address :: binary(),
          fields :: list(),
          opts :: list(),
          db_path :: String.t()
        ) ::
          {transactions_by_page :: list(Transaction.t()), more? :: boolean(),
           paging_state :: nil | binary()}
  def get_transaction_chain(address, fields, opts, db_path) do
    start = System.monotonic_time()

    case ChainIndex.get_tx_entry(address, db_path) do
      {:error, :not_exists} ->
        {[], false, ""}

      {:ok, %{genesis_address: genesis_address}} ->
        filepath = ChainWriter.chain_path(db_path, genesis_address)
        fd = File.open!(filepath, [:binary, :read])

        {transactions, more?, paging_state} =
          process_get_chain(fd, address, fields, opts, db_path)

        :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
          query: "get_transaction_chain"
        })

        {transactions, more?, paging_state}
    end
  end

  @spec get_transaction_chain_desc(
          address :: binary(),
          fields :: list(),
          opts :: list(),
          db_path :: String.t()
        ) ::
          {transactions_by_page :: list(Transaction.t()), more? :: boolean(),
           paging_state :: nil | binary()}
  def get_transaction_chain_desc(address, fields, opts, db_path) do
    start = System.monotonic_time()

    # Always return transaction address
    fields = if Enum.empty?(fields), do: fields, else: Enum.uniq([:address | fields])
    column_names = fields_to_column_names(fields)

    case ChainIndex.get_tx_entry(address, db_path) do
      {:error, :not_exists} ->
        {[], false, ""}

      {:ok, %{genesis_address: genesis_address}} ->
        filepath = ChainWriter.chain_path(db_path, genesis_address)
        fd = File.open!(filepath, [:binary, :read])

        all_addresses = ChainIndex.list_chain_addresses(genesis_address, db_path)

        next_addresses =
          case Keyword.get(opts, :paging_state) do
            nil ->
              all_addresses
              |> Enum.to_list()
              |> Enum.reverse()

            paging_state ->
              all_addresses
              |> Enum.to_list()
              |> Enum.reverse()
              |> Enum.drop_while(fn {addr, _} -> addr != paging_state end)
              |> Enum.drop(1)
          end

        next_addresses_limited =
          Enum.take(next_addresses, Keyword.get(opts, :transactions_per_page, 10))

        more? = length(next_addresses_limited) < length(next_addresses)
        paging_state = List.last(next_addresses_limited, "")

        transactions =
          next_addresses_limited
          |> Enum.map(fn {addr, _timestamp} ->
            {:ok, %{offset: offset}} = ChainIndex.get_tx_entry(addr, db_path)

            :file.position(fd, offset)
            {:ok, <<size::32, version::32>>} = :file.read(fd, 8)

            fd
            |> read_transaction(column_names, size, 0)
            |> decode_transaction_columns(version)
          end)

        :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
          query: "get_transaction_chain_desc"
        })

        {transactions, more?, paging_state}
    end
  end

  @doc """
  List all the transactions in io storage
  """
  @spec list_io_transactions(fields :: list(), db_path :: String.t()) ::
          Enumerable.t() | list(Transaction.t())
  def list_io_transactions(fields, db_path) do
    io_transactions_path =
      ChainWriter.base_io_path(db_path)
      |> Path.join("*")
      |> Path.wildcard()

    Stream.resource(
      fn -> io_transactions_path end,
      fn
        [filepath | rest] -> {[read_io_transaction(filepath, fields)], rest}
        [] -> {:halt, nil}
      end,
      fn _ -> :ok end
    )
  end

  defp read_io_transaction(filepath, fields) do
    # Open the file as the position from the transaction in the chain file
    fd = File.open!(filepath, [:binary, :read])

    {:ok, <<size::32, version::32>>} = :file.read(fd, 8)
    column_names = fields_to_column_names(fields)

    # Ensure the validation stamp's protocol version is retrieved if we fetch validation stamp fields
    has_validation_stamp_fields? =
      Enum.any?(column_names, &String.starts_with?(&1, "validation_stamp."))

    has_validation_stamp_protocol_field? =
      Enum.any?(column_names, &(&1 == "validation_stamp.protocol_version"))

    column_names =
      if has_validation_stamp_fields? and !has_validation_stamp_protocol_field? do
        ["validation_stamp.protocol_version" | column_names]
      else
        column_names
      end

    # Read the transaction and extract requested columns from the fields arg
    tx =
      fd
      |> read_transaction(column_names, size, 0)
      |> Enum.into(%{})
      |> decode_transaction_columns(version)

    :file.close(fd)

    tx
  end

  defp process_get_chain(fd, address, fields, opts, db_path) do
    # Set the file cursor position to the paging state
    case Keyword.get(opts, :paging_state) do
      nil ->
        :file.position(fd, 0)
        do_process_get_chain(fd, address, fields)

      paging_address ->
        case ChainIndex.get_tx_entry(paging_address, db_path) do
          {:ok, %{offset: offset, size: size}} ->
            :file.position(fd, offset + size)
            do_process_get_chain(fd, address, fields)

          {:error, :not_exists} ->
            {[], false, ""}
        end
    end
  end

  defp do_process_get_chain(fd, address, fields) do
    # Always return transaction address
    fields = if Enum.empty?(fields), do: fields, else: Enum.uniq([:address | fields])

    column_names = fields_to_column_names(fields)

    # Ensure the validation stamp's protocol version is retrieved if we fetch validation stamp fields
    has_validation_stamp_fields? =
      Enum.any?(column_names, &String.starts_with?(&1, "validation_stamp."))

    has_validation_stamp_protocol_field? =
      Enum.any?(column_names, &(&1 == "validation_stamp.protocol_version"))

    column_names =
      if has_validation_stamp_fields? and !has_validation_stamp_protocol_field? do
        ["validation_stamp.protocol_version" | column_names]
      else
        column_names
      end

    # Read the transactions until the nb of transactions to fullfil the page (ie. 10 transactions)
    {transactions, more?, paging_state} = do_scan_chain(fd, column_names, address)
    :file.close(fd)

    {transactions, more?, paging_state}
  end

  defp read_transaction(fd, fields, limit, position, acc \\ %{})

  defp read_transaction(_fd, _fields, limit, position, acc) when limit == position, do: acc

  defp read_transaction(fd, fields, limit, position, acc) do
    case :file.read(fd, 1) do
      {:ok, <<column_name_size::8>>} ->
        {:ok, <<value_size::32>>} = :file.read(fd, 4)

        {:ok, <<column_name::binary-size(column_name_size), value::binary-size(value_size)>>} =
          :file.read(fd, column_name_size + value_size)

        position = position + 5 + column_name_size + value_size

        # Without field selection we take all the fields of the transaction
        if fields == [] do
          read_transaction(fd, fields, limit, position, Map.put(acc, column_name, value))
        else
          # Check if we need to take this field based on the selection criteria
          if column_name in fields do
            read_transaction(fd, fields, limit, position, Map.put(acc, column_name, value))
          else
            # We continue to the next as the selection critieria didn't match
            read_transaction(fd, fields, limit, position, acc)
          end
        end

      :eof ->
        acc
    end
  end

  @doc """
  Read chain from the beginning until a given limit address
  """
  @spec scan_chain(
          genesis_address :: binary(),
          limit_address :: nil | binary(),
          fields :: list(),
          paging_address :: nil | binary(),
          db_path :: binary()
        ) ::
          {list(Transaction.t()), boolean(), binary() | nil}
  def scan_chain(genesis_address, limit_address, fields, paging_address, db_path) do
    filepath = ChainWriter.chain_path(db_path, genesis_address)
    # Always return transaction address
    fields = if Enum.empty?(fields), do: fields, else: Enum.uniq([:address | fields])

    column_names = fields_to_column_names(fields)

    case File.open(filepath, [:binary, :read]) do
      {:ok, fd} ->
        if paging_address do
          case ChainIndex.get_tx_entry(paging_address, db_path) do
            {:ok, %{offset: offset, size: size}} ->
              :file.position(fd, offset + size)
              do_scan_chain(fd, column_names, limit_address)

            {:error, :not_exists} ->
              {[], false, ""}
          end
        else
          do_scan_chain(fd, column_names, limit_address)
        end

      {:error, _} ->
        {[], false, nil}
    end
  end

  defp do_scan_chain(fd, fields, limit_address, acc \\ []) do
    case :file.read(fd, 8) do
      {:ok, <<size::32, version::32>>} ->
        if length(acc) == @page_size do
          %Transaction{address: address} = List.first(acc)
          {Enum.reverse(acc), true, address}
        else
          tx =
            fd
            |> read_transaction(fields, size, 0)
            |> decode_transaction_columns(version)

          if tx.address == limit_address do
            {Enum.reverse([tx | acc]), false, nil}
          else
            do_scan_chain(fd, fields, limit_address, [tx | acc])
          end
        end

      :eof ->
        {Enum.reverse(acc), false, nil}
    end
  end

  @doc """
  Stream chain tx from the beginning until a given limit address
  """
  @spec stream_scan_chain(
          genesis_address :: binary(),
          limit_address :: nil | binary(),
          fields :: list(),
          db_path :: binary()
        ) :: Enumerable.t()
  def stream_scan_chain(genesis_address, limit_address, fields, db_path) do
    Stream.resource(
      fn -> scan_chain(genesis_address, limit_address, fields, nil, db_path) end,
      fn
        {transactions, true, paging_state} ->
          {transactions,
           scan_chain(genesis_address, limit_address, fields, paging_state, db_path)}

        {transactions, false, _} ->
          {transactions, :eof}

        :eof ->
          {:halt, nil}
      end,
      fn _ -> :ok end
    )
  end

  @doc """

  ## Examples

      iex> ChainReader.fields_to_column_names([:address, :previous_public_key, validation_stamp: [:timestamp]])
      [
         "address",
         "previous_public_key",
         "validation_stamp.timestamp"
      ]

      iex> ChainReader.fields_to_column_names([:address, :previous_public_key, validation_stamp: [ledger_operations: [:fee,  :transaction_movements]]])
      [
         "address",
         "previous_public_key",
         "validation_stamp.ledger_operations.transaction_movements",
         "validation_stamp.ledger_operations.fee",
      ]

      iex> ChainReader.fields_to_column_names([
      ...>  :address,
      ...>  :previous_public_key,
      ...>  data: [:content],
      ...>  validation_stamp: [
      ...>    :timestamp,
      ...>    ledger_operations: [ :fee,  :transaction_movements ]
      ...>  ]
      ...> ])
      [
         "address",
         "previous_public_key",
         "data.content",
         "validation_stamp.ledger_operations.transaction_movements",
         "validation_stamp.ledger_operations.fee",
         "validation_stamp.timestamp"
      ]
  """
  @spec fields_to_column_names(list()) :: list(binary())
  def fields_to_column_names(_fields, acc \\ [], prepend \\ "")

  def fields_to_column_names([{k, v} | rest], acc, prepend = "") do
    fields_to_column_names(
      rest,
      List.flatten([fields_to_column_names(v, [], Atom.to_string(k)) | acc]),
      prepend
    )
  end

  def fields_to_column_names([{k, v} | rest], acc, prepend) do
    nested_prepend = "#{prepend}.#{Atom.to_string(k)}"

    fields_to_column_names(
      rest,
      [fields_to_column_names(v, [], nested_prepend) | acc],
      prepend
    )
  end

  def fields_to_column_names([key | rest], acc, prepend = "") do
    fields_to_column_names(rest, [Atom.to_string(key) | acc], prepend)
  end

  def fields_to_column_names([key | rest], acc, prepend) do
    fields_to_column_names(rest, ["#{prepend}.#{Atom.to_string(key)}" | acc], prepend)
  end

  def fields_to_column_names([], acc, _prepend) do
    Enum.reverse(acc)
  end

  def fields_to_column_names(field, acc, prepend) do
    fields_to_column_names([], ["#{prepend}.#{Atom.to_string(field)}" | acc])
  end

  defp decode_transaction_columns(tx_columns, tx_version) do
    <<protocol_version::32>> = Map.get(tx_columns, "validation_stamp.protocol_version", <<1::32>>)

    Enum.reduce(
      tx_columns,
      %{version: tx_version, validation_stamp: %{protocol_version: protocol_version}},
      fn {column, data}, acc ->
        if String.starts_with?(column, "validation_stamp.") do
          Encoding.decode(
            protocol_version,
            column,
            data,
            acc
          )
        else
          Encoding.decode(tx_version, column, data, acc)
        end
      end
    )
    |> Utils.atomize_keys()
    |> Transaction.cast()
  end
end
