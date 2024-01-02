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

        File.close(fd)

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

  @doc """
  Return a transaction chain.
  By default, order is chronological (ASC)

  Opts:
    paging_address :: binary()
    order :: :asc | :desc
  """
  @spec get_transaction_chain(
          address :: binary(),
          fields :: list(),
          opts :: list(),
          db_path :: String.t()
        ) ::
          {transactions_by_page :: list(Transaction.t()), more? :: boolean(),
           paging_address :: nil | binary()}
  def get_transaction_chain(address, fields, opts, db_path) do
    start = System.monotonic_time()

    genesis_address = ChainIndex.get_genesis_address(address, db_path)
    filepath = ChainWriter.chain_path(db_path, genesis_address)

    if File.exists?(filepath) do
      fd = File.open!(filepath, [:binary, :read])

      {transactions, more?, paging_address} =
        case Keyword.get(opts, :order, :asc) do
          :asc ->
            process_get_chain(fd, fields, opts, db_path)

          :desc ->
            process_get_chain_desc(fd, genesis_address, fields, opts, db_path)
        end

      File.close(fd)

      # we want different metrics for ASC and DESC
      :telemetry.execute([:archethic, :db], %{duration: System.monotonic_time() - start}, %{
        query:
          case Keyword.get(opts, :order, :asc) do
            :asc -> "get_transaction_chain"
            :desc -> "get_transaction_chain_reverse"
          end
      })

      {transactions, more?, paging_address}
    else
      {[], false, nil}
    end
  end

  @doc """
  Stream chain tx from the beginning
  """
  @spec stream_chain(
          genesis_address :: binary(),
          fields :: list(),
          db_path :: binary()
        ) :: Enumerable.t() | list(Transaction.t())
  def stream_chain(genesis_address, fields, db_path) do
    filepath = ChainWriter.chain_path(db_path, genesis_address)

    case File.open(filepath, [:binary, :read]) do
      {:ok, fd} ->
        Stream.resource(
          fn -> process_get_chain(fd, fields, [], db_path) end,
          fn
            {transactions, true, paging_address} ->
              next_transactions =
                process_get_chain(
                  fd,
                  fields,
                  [paging_address: paging_address],
                  db_path
                )

              {transactions, next_transactions}

            {transactions, false, _} ->
              {transactions, :eof}

            :eof ->
              {:halt, nil}
          end,
          fn _ -> File.close(fd) end
        )

      {:error, _} ->
        []
    end
  end

  @doc """
  Read a transaction from io storage
  """
  @spec get_io_transaction(binary(), fields :: list(), db_path :: String.t()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_io_transaction(address, fields, db_path) do
    filepath = ChainWriter.io_path(db_path, address)

    if File.exists?(filepath) do
      {:ok, read_io_transaction(filepath, fields)}
    else
      {:error, :transaction_not_exists}
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

    File.close(fd)

    tx
  end

  defp process_get_chain(fd, fields, opts, db_path) do
    # Set the file cursor position to the paging state
    case Keyword.get(opts, :paging_address) do
      nil ->
        :file.position(fd, 0)
        do_process_get_chain(fd, fields)

      paging_address ->
        case ChainIndex.get_tx_entry(paging_address, db_path) do
          {:ok, %{offset: offset, size: size}} ->
            :file.position(fd, offset + size)
            do_process_get_chain(fd, fields)

          {:error, :not_exists} ->
            {[], false, nil}
        end
    end
  end

  defp do_process_get_chain(fd, fields) do
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
    {transactions, more?, paging_address} = get_paginated_chain(fd, column_names)

    {transactions, more?, paging_address}
  end

  # in order to read the file sequentially in DESC (faster than random access)
  # we have to determine the correct paging_address and limit_address
  # then we can use the process_get_chain that does the ASC read
  defp process_get_chain_desc(fd, genesis_address, fields, opts, db_path) do
    all_addresses_asc =
      ChainIndex.list_chain_addresses(genesis_address, db_path)
      |> Enum.map(&elem(&1, 0))

    {nb_to_take, paging_address, more?, new_paging_address} =
      case Keyword.get(opts, :paging_address) do
        nil ->
          chain_length = Enum.count(all_addresses_asc)

          if chain_length <= @page_size do
            {@page_size, nil, false, nil}
          else
            idx = chain_length - 1 - @page_size

            paging_address = all_addresses_asc |> Enum.at(idx)
            new_paging_address = all_addresses_asc |> Enum.at(idx + 1)

            {@page_size, paging_address, true, new_paging_address}
          end

        paging_address ->
          paging_address_idx =
            all_addresses_asc
            |> Enum.find_index(&(&1 == paging_address))

          if paging_address_idx <= @page_size do
            {paging_address_idx, nil, false, nil}
          else
            idx = paging_address_idx - 1 - @page_size

            paging_address = all_addresses_asc |> Enum.at(idx)
            new_paging_address = all_addresses_asc |> Enum.at(idx + 1)

            {@page_size, paging_address, true, new_paging_address}
          end
      end

    # call the ASC function and ignore the more? and paging_address
    {transactions, _more?, _paging_address} =
      process_get_chain(fd, fields, [paging_address: paging_address], db_path)

    transactions = Enum.take(transactions, nb_to_take)

    {Enum.reverse(transactions), more?, new_paging_address}
  end

  defp get_paginated_chain(fd, fields, acc \\ []) do
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

          get_paginated_chain(fd, fields, [tx | acc])
        end

      :eof ->
        {Enum.reverse(acc), false, nil}
    end
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
          cond do
            column_name in fields ->
              # match a field
              read_transaction(fd, fields, limit, position, Map.put(acc, column_name, value))

            Enum.any?(fields, &String.starts_with?(column_name, &1 <> ".")) ->
              # match a nested field
              read_transaction(fd, fields, limit, position, Map.put(acc, column_name, value))

            true ->
              # We continue to the next as the selection critieria didn't match
              read_transaction(fd, fields, limit, position, acc)
          end
        end

      :eof ->
        acc
    end
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
