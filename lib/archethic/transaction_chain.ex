defmodule Archethic.TransactionChain do
  @moduledoc """
  Handle the logic managing transaction chain

  Some functions have a prefix with a specific meaning:
  - list -> request not related to a specific chain
  - get -> get data from DB
  - fetch -> if data is immuable, first get data from DB, if not present request it on the network
             if data evolve over time, always request it on the network
  All functions that may return a list always return a stream
  """

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Node

  alias Archethic.P2P.Message.{
    AddressList,
    Error,
    GenesisAddress,
    GetGenesisAddress,
    GetLastTransactionAddress,
    GetNextAddresses,
    GetTransaction,
    GetTransactionChain,
    GetTransactionChainLength,
    GetTransactionInputs,
    GetTransactionSummary,
    GetUnspentOutputs,
    LastTransactionAddress,
    NotFound,
    TransactionChainLength,
    TransactionInputList,
    TransactionList,
    TransactionSummaryMessage,
    UnspentOutputList,
    GetFirstTransactionAddress,
    FirstTransactionAddress
  }

  alias __MODULE__.MemTables.KOLedger
  alias __MODULE__.MemTables.PendingLedger
  # alias __MODULE__.MemTablesLoader

  alias Archethic.TaskSupervisor

  alias __MODULE__.Transaction
  alias __MODULE__.TransactionData
  alias __MODULE__.Transaction.ValidationStamp

  alias __MODULE__.Transaction.ValidationStamp.LedgerOperations
  alias __MODULE__.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  alias __MODULE__.TransactionSummary
  alias __MODULE__.VersionedTransactionInput
  alias __MODULE__.DBLedger

  alias Archethic.Utils

  require Logger

  @type search_mode :: :hybrid | :remote

  @type search_options :: [
          timeout: non_neg_integer(),
          acceptance_resolver: (any() -> boolean()),
          consistency_level: pos_integer(),
          search_mode: search_mode()
        ]

  # ------------------------------------------------------------
  #   _     ___ ____ _____
  #  | |   |_ _/ ___|_   _|
  #  | |    | |\___ \ | |
  #  | |___ | | ___) || |
  #  |_____|___|____/ |_|
  # ------------------------------------------------------------

  @doc """
  List all the transaction chain stored. Chronological order within a transaction chain
  """
  @spec list_all(fields :: list()) :: Enumerable.t()
  defdelegate list_all(fields \\ []), to: DB, as: :list_transactions

  @doc """
  List all the genesis addresses
  """
  @spec list_genesis_addresses() :: Enumerable.t()
  defdelegate list_genesis_addresses(), to: DB

  @doc """
  List all the io transactions stored
  """
  @spec list_io_transactions(fields :: list()) :: Enumerable.t()
  defdelegate list_io_transactions(fields \\ []), to: DB

  @doc """
  List all the transaction for a given transaction type sorted by timestamp in descent order
  """
  @spec list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t()
  defdelegate list_transactions_by_type(type, fields), to: DB

  @doc """
  Stream all the addresses for a transaction type
  """
  @spec list_addresses_by_type(Transaction.transaction_type()) :: Enumerable.t() | list(binary())
  defdelegate list_addresses_by_type(type), to: DB

  @doc """
  Stream all the addresses in chronological belonging to a genesis address
  """
  @spec list_chain_addresses(binary()) :: Enumerable.t() | list({binary(), DateTime.t()})
  defdelegate list_chain_addresses(genesis_address), to: DB

  @doc """
  Stream all the public keys until a date, from a public key.
  """
  @spec list_chain_public_keys(binary(), DateTime.t()) ::
          Enumerable.t() | list({binary(), DateTime.t()})
  defdelegate list_chain_public_keys(first_public_key, until), to: DB

  @doc """
  Stream first transactions address of a chain from genesis_address.
  The Genesis Addresses is not a transaction or the first transaction.
  The first transaction is calulated by index = 0+1
  """
  @spec list_first_addresses() :: Enumerable.t() | list(Crypto.prepended_hash())
  defdelegate list_first_addresses(), to: DB

  # ------------------------------------------------------------
  #    ____ _____ _____
  #   / ___| ____|_   _|
  #  | |  _|  _|   | |
  #  | |_| | |___  | |
  #   \____|_____| |_|
  # ------------------------------------------------------------

  @doc """
  Get the last transaction address from a transaction chain with the latest time
  """
  @spec get_last_address(binary()) :: {binary(), DateTime.t()}
  defdelegate get_last_address(address), to: DB, as: :get_last_chain_address

  @doc """
  Get the last transaction address from a transaction chain before a given date along its last time
  """
  @spec get_last_address(binary(), DateTime.t()) :: {binary(), DateTime.t()}
  defdelegate get_last_address(address, timestamp), to: DB, as: :get_last_chain_address

  @doc """
  Get the first public key from one the public key of the chain
  """
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  defdelegate get_first_public_key(previous_public_key), to: DB

  @doc """
  Get a transaction

  A lookup is performed into the KO ledger to determine if the transaction is invalid
  """
  @spec get_transaction(binary(), fields :: list()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :invalid_transaction}
  def get_transaction(address, fields \\ [], storage_type \\ :chain) when is_list(fields) do
    if KOLedger.has_transaction?(address) do
      {:error, :invalid_transaction}
    else
      DB.get_transaction(address, fields, storage_type)
    end
  end

  @doc """
  Get the last transaction from a given chain address
  """
  @spec get_last_transaction(binary(), list()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :invalid_transaction}
  def get_last_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    {address, _} = get_last_address(address)
    get_transaction(address, fields)
  end

  @doc """
  Get the first transaction Address from a genesis/chain address
  """
  @spec get_first_transaction_address(address :: binary()) ::
          {:ok, {address :: binary(), DateTime.t()}} | {:error, :transaction_not_exists}
  def get_first_transaction_address(address) when is_binary(address) do
    address =
      address
      |> get_genesis_address()
      |> list_chain_addresses()
      |> Enum.at(0)

    case address do
      nil -> {:error, :transaction_not_exists}
      {address, datetime} -> {:ok, {address, datetime}}
    end
  end

  @doc """
  Get the genesis address from a given chain address

  If no genesis address is found, the given address is returned by default
  """
  @spec get_genesis_address(address :: Crypto.prepended_hash()) ::
          genesis_address :: Crypto.prepended_hash()
  defdelegate get_genesis_address(address), to: DB

  @doc """
  Get the genesis address from a given chain address
  """
  @spec find_genesis_address(address :: Crypto.prepended_hash()) ::
          {:ok, genesis_address :: Crypto.prepended_hash()} | {:error, :not_found}
  defdelegate find_genesis_address(address), to: DB

  @doc """
  Retrieve the last transaction address for a chain stored locally
  """
  @spec get_last_stored_address(genesis_address :: Crypto.prepended_hash()) ::
          Crypto.prepended_hash() | nil
  defdelegate get_last_stored_address(genesis_address), to: DB, as: :get_last_chain_address_stored

  @doc """
  Get a transaction summary from a transaction address
  """
  @spec get_transaction_summary(binary()) :: {:ok, TransactionSummary.t()} | {:error, :not_found}
  def get_transaction_summary(address) do
    case get_transaction(address, [
           :address,
           :type,
           :validation_stamp
         ]) do
      {:ok, tx} ->
        {:ok, TransactionSummary.from_transaction(tx, get_genesis_address(address))}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Stream the transactions from a chain
  """
  @spec get(binary(), list()) :: Enumerable.t() | list(Transaction.t())
  defdelegate get(address, fields \\ []), to: DB, as: :stream_chain

  @doc """
  Return the size of transaction chain
  """
  @spec get_size(binary()) :: non_neg_integer()
  defdelegate get_size(address), to: DB, as: :chain_size

  @doc """
  Get the details from a ko transaction address
  """
  @spec get_ko_details(binary()) ::
          {ValidationStamp.t(), inconsistencies :: list(), errors :: list()}
  defdelegate get_ko_details(address), to: KOLedger, as: :get_details

  @doc """
  List of all the counter signatures regarding a given transaction
  """
  @spec get_signatures_for_pending_transaction(binary()) :: list(binary())
  defdelegate get_signatures_for_pending_transaction(address),
    to: PendingLedger,
    as: :get_signatures

  # ------------------------------------------------------------
  #   _____ _____ _____ ____ _   _
  #  |  ___| ____|_   _/ ___| | | |
  #  | |_  |  _|   | || |   | |_| |
  #  |  _| | |___  | || |___|  _  |
  #  |_|   |_____| |_| \____|_| |_|
  # ------------------------------------------------------------

  @doc """
  Fetch the last address remotely.
  """
  @spec fetch_last_address(
          address :: binary(),
          storage_nodes :: list(Node.t()),
          options :: [timestamp :: DateTime.t()] | search_options()
        ) ::
          {:ok, binary()} | {:error, :network_issue | :acceptance_failed}
  def fetch_last_address(address, nodes, opts \\ []) when is_binary(address) and is_list(nodes) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    timeout = Keyword.get(opts, :timeout, 0)
    consistency_level = Keyword.get(opts, :consistency_level, 3)
    acceptance_resolver = Keyword.get(opts, :acceptance_resolver, fn _ -> true end)

    conflict_resolver = fn results ->
      Enum.max_by(results, &DateTime.to_unix(&1.timestamp, :millisecond))
    end

    case P2P.quorum_read(
           nodes,
           %GetLastTransactionAddress{address: address, timestamp: timestamp},
           conflict_resolver,
           timeout,
           acceptance_resolver,
           consistency_level
         ) do
      {:ok, %LastTransactionAddress{address: last_address}} ->
        {:ok, last_address}

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Request the chain addresses from paging address to last chain address
  """
  @spec fetch_next_chain_addresses(
          address :: Crypto.prepended_hash(),
          storage_nodes :: list(Node.t()),
          opts :: [limit: non_neg_integer()] | search_options()
        ) ::
          {:ok, list({address :: Crypto.prepended_hash(), timestamp :: DateTime.t()})}
          | {:error, :network_issue}
  def fetch_next_chain_addresses(address, nodes, opts \\ []) do
    limit = Keyword.get(opts, :limit, 0)

    with :hybrid <- Keyword.get(opts, :search_mode, :hybrid),
         addresses when addresses != [] <- get_next_addresses(address, limit) do
      {:ok, addresses}
    else
      _ ->
        conflict_resolver = fn results ->
          Enum.sort_by(results, &length(&1.addresses), :desc) |> List.first()
        end

        case P2P.quorum_read(
               nodes,
               %GetNextAddresses{address: address, limit: limit},
               conflict_resolver
             ) do
          {:ok, %AddressList{addresses: addresses}} -> {:ok, addresses}
          {:error, :network_issue} = e -> e
        end
    end
  end

  @doc """
  Fetch transaction remotely

  If the transaction exists, then its value is returned in the shape of `{:ok, transaction}`.
  If the transaction doesn't exist, `{:error, :transaction_not_exists}` is returned.
  If no nodes are available to answer the request, `{:error, :network_issue}` is returned.

  Options:
  - search_mode: select where to request the data: :remote or :hybrid (default :hybrid)
  - timeout: set the timeout for the remote request (default Message.max_timeout)
  - acceptance_resolver: set the function to accept the result of the quorum (default fn _ -> true end)
  """
  @spec fetch_transaction(
          address :: Crypto.prepended_hash(),
          storage_nodes :: list(Node.t()),
          search_options()
        ) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :invalid_transaction}
          | {:error, :network_issue}
  def fetch_transaction(address, nodes, opts \\ []) do
    with :hybrid <- Keyword.get(opts, :search_mode, :hybrid),
         {:ok, tx} <- get_transaction(address) do
      {:ok, tx}
    else
      _ ->
        timeout = Keyword.get(opts, :timeout, Message.get_max_timeout())
        acceptance_resolver = Keyword.get(opts, :acceptance_resolver, fn _ -> true end)

        conflict_resolver = fn results ->
          Enum.reduce(results, fn
            %NotFound{}, acc ->
              acc

            err = %Error{}, %NotFound{} ->
              # prioritize error over not_found
              err

            %Error{}, acc ->
              acc

            tx, %NotFound{} ->
              tx

            tx1, tx2 ->
              if acceptance_resolver.(tx1) do
                tx1
              else
                # even if tx2 is not accepted
                # we let it win this conflict
                # it'll raise an :acceptance_failed error later
                tx2
              end
          end)
        end

        case P2P.quorum_read(
               nodes,
               %GetTransaction{address: address},
               conflict_resolver,
               timeout,
               acceptance_resolver
             ) do
          {:ok, %NotFound{}} ->
            {:error, :transaction_not_exists}

          {:ok, %Error{}} ->
            {:error, :invalid_transaction}

          res ->
            res
        end
    end
  end

  @doc """
  Stream a transaction chain from the paging state
  """
  @spec fetch(
          last_chain_address :: Crypto.prepended_hash(),
          storage_nodes :: list(Node.t()),
          pagination_options :: [paging_state: binary(), order: :asc | :desc]
        ) ::
          Enumerable.t() | list(Transaction.t())
  def fetch(last_chain_address, nodes, opts \\ []) do
    paging_state = Keyword.get(opts, :paging_state, nil)
    order = Keyword.get(opts, :order, :asc)

    case resolve_paging_state(last_chain_address, paging_state, order) do
      {:ok, paging_address} -> do_fetch(last_chain_address, nodes, paging_address, order)
      {:error, :not_in_local} -> do_fetch(last_chain_address, nodes, paging_state, order)
      {:error, :not_exists} -> []
    end
  end

  defp do_fetch(last_chain_address, nodes, paging_state, order = :asc) do
    in_db? =
      case paging_state do
        %DateTime{} -> false
        nil -> get_genesis_address(last_chain_address) != last_chain_address
        paging_address -> transaction_exists?(paging_address)
      end

    next_iteration = fn transactions, more?, next_paging_address ->
      # Catch when the local DB reached the end of the chain but there is still transaction in the chain
      if more? do
        {transactions, {next_paging_address, more?, true}}
      else
        case List.last(transactions) do
          %Transaction{address: ^last_chain_address} ->
            {transactions, {nil, false, true}}

          nil ->
            {[], {next_paging_address, true, false}}

          %Transaction{address: next_paging_address} ->
            {transactions, {next_paging_address, true, false}}
        end
      end
    end

    Stream.resource(
      fn -> {paging_state, true, in_db?} end,
      fn
        {paging_state, _more? = true, _in_db? = false} ->
          # More to fetch but not in db
          {transactions, more?, next_paging_address} =
            request_transaction_chain(last_chain_address, nodes, paging_state, order)

          {transactions, {next_paging_address, more?, false}}

        {_paging_state = nil, _more? = true, _in_db? = true} ->
          # More to fetch from DB using last_chain address as it is first time requesting the DB
          {transactions, more?, next_paging_address} =
            DB.get_transaction_chain(last_chain_address, [], order: order)

          next_iteration.(transactions, more?, next_paging_address)

        {paging_address, _more? = true, _in_db? = true} ->
          # More to fetch from DB using paging address
          {transactions, more?, next_paging_address} =
            DB.get_transaction_chain(paging_address, [],
              paging_address: paging_address,
              order: order
            )

          next_paging_address =
            if Enum.empty?(transactions), do: paging_address, else: next_paging_address

          next_iteration.(transactions, more?, next_paging_address)

        {_, _more? = false, _} ->
          # No more to fetch
          {:halt, nil}
      end,
      fn _ -> :ok end
    )
  end

  defp do_fetch(last_chain_address, nodes, paging_state, order = :desc) do
    in_db? =
      case paging_state do
        %DateTime{} -> false
        nil -> transaction_exists?(last_chain_address)
        paging_address -> transaction_exists?(paging_address)
      end

    Stream.resource(
      fn -> {paging_state, true, in_db?} end,
      fn
        {paging_state, _more? = true, _in_db? = false} ->
          # More to fetch but not in db
          {transactions, more?, next_paging_address} =
            request_transaction_chain(last_chain_address, nodes, paging_state, order)

          next_in_db? =
            if next_paging_address != nil,
              do: transaction_exists?(next_paging_address),
              else: false

          {transactions, {next_paging_address, more?, next_in_db?}}

        {_paging_state = nil, _more? = true, _in_db? = true} ->
          # More to fetch from DB using last_chain address as it is first time requesting the DB
          {transactions, more?, next_paging_address} =
            DB.get_transaction_chain(last_chain_address, [], order: order)

          {transactions, {next_paging_address, more?, true}}

        {paging_address, _more? = true, _in_db? = true} ->
          # More to fetch from DB using paging address
          {transactions, more?, next_paging_address} =
            DB.get_transaction_chain(paging_address, [],
              paging_address: paging_address,
              order: order
            )

          {transactions, {next_paging_address, more?, true}}

        {_, _more? = false, _} ->
          # No more to fetch
          {:halt, nil}
      end,
      fn _ -> :ok end
    )
  end

  defp request_transaction_chain(last_chain_address, nodes, paging_state, order) do
    conflict_resolver = fn results ->
      results
      |> Enum.sort(
        # Prioritize more? at true
        # then length of transaction list
        # then regarding order, the oldest or newest transaction timestamp
        # of the first element of the list
        &with false <- &1.more? and !&2.more?,
              false <- length(&1.transactions) > length(&2.transactions) do
          if Enum.empty?(&1.transactions) do
            false
          else
            case order do
              :asc ->
                DateTime.compare(
                  List.first(&1.transactions).validation_stamp.timestamp,
                  List.first(&2.transactions).validation_stamp.timestamp
                ) == :lt

              :desc ->
                DateTime.compare(
                  List.first(&1.transactions).validation_stamp.timestamp,
                  List.first(&2.transactions).validation_stamp.timestamp
                ) == :gt
            end
          end
        end
      )
      |> List.first()
    end

    # We got transactions by batch of 10 transactions
    timeout = Message.get_max_timeout() + Message.get_max_timeout() * 10

    case P2P.quorum_read(
           nodes,
           %GetTransactionChain{
             address: last_chain_address,
             paging_state: paging_state,
             order: order
           },
           conflict_resolver,
           timeout
         ) do
      {:ok,
       %TransactionList{
         transactions: transactions,
         more?: more?,
         paging_address: next_paging_address
       }} ->
        {transactions, more?, next_paging_address}

      error ->
        Logger.warning("failed to fetch transaction chain: #{inspect(error)}")
        {[], false, nil}
    end
  end

  @doc """
  Stream the transaction inputs for a transaction address

  If the inputs exist, then they are returned in the shape of `{:ok, inputs}`.
  If no nodes are able to answer the request, `{:error, :network_issue}` is returned.
  """
  @spec fetch_inputs(
          address :: Crypto.prepended_hash(),
          storage_nodes :: list(Node.t()),
          offset :: non_neg_integer(),
          limit :: non_neg_integer()
        ) :: Enumerable.t() | list(VersionedTransactionInput.t())
  def fetch_inputs(address, nodes, offset \\ 0, limit \\ 0)
  def fetch_inputs(_, [], _, _), do: []

  def fetch_inputs(address, nodes, offset, limit) do
    Stream.resource(
      fn -> {limit, do_fetch_inputs(address, nodes, offset, limit)} end,
      fn
        {previous_limit, {inputs, true, offset}} ->
          new_limit = previous_limit - length(inputs)

          if new_limit <= 0 do
            {inputs, :eof}
          else
            {inputs, {new_limit, do_fetch_inputs(address, nodes, offset, limit)}}
          end

        {_, {inputs, false, _}} ->
          {inputs, :eof}

        :eof ->
          {:halt, nil}
      end,
      fn _ -> :ok end
    )
  end

  defp do_fetch_inputs(address, nodes, offset, limit)
       when is_binary(address) and is_list(nodes) and is_integer(offset) and offset >= 0 and
              is_integer(limit) and limit >= 0 do
    local_inputs = get_inputs(address)

    case local_inputs do
      [] ->
        fetch_remote_inputs(address, nodes, offset, limit)

      _ ->
        {inputs, more?, offset} =
          local_inputs
          |> Enum.sort_by(& &1.input.timestamp, {:desc, DateTime})
          |> Utils.limit_list(limit, offset)

        {inputs, more?, offset}
    end
  end

  defp fetch_remote_inputs(address, nodes, offset, limit) do
    conflict_resolver = fn results ->
      results
      |> Enum.sort_by(&length(&1.inputs), :desc)
      |> List.first()
    end

    case P2P.quorum_read(
           nodes,
           %GetTransactionInputs{address: address, offset: offset, limit: limit},
           conflict_resolver
         ) do
      {:ok, %TransactionInputList{inputs: versioned_inputs, more?: more?, offset: offset}} ->
        {versioned_inputs, more?, offset}

      {:error, :network_issue} ->
        {[], false, 0}
    end
  end

  @doc """
  Stream the transaction unspent outputs for a transaction address
  """
  @spec fetch_unspent_outputs(
          address :: Crypto.prepended_hash(),
          nodes :: list(Node.t()),
          opts :: Keyword.t()
        ) :: Enumerable.t() | list(VersionedUnspentOutput.t())
  def fetch_unspent_outputs(address, nodes, opts \\ [])
  def fetch_unspent_outputs(_, [], _), do: []

  def fetch_unspent_outputs(address, nodes, opts)
      when is_binary(address) and is_list(nodes) and is_list(opts) do
    offset = Keyword.get(opts, :paging_offset, nil)
    limit = Keyword.get(opts, :limit, 0)

    Stream.resource(
      fn -> {limit, do_fetch_unspent_outputs(address, nodes, offset, limit)} end,
      fn
        {previous_limit, {utxos, true, offset}} ->
          new_limit = previous_limit - length(utxos)

          if new_limit <= 0 do
            {utxos, :eof}
          else
            {utxos, {new_limit, do_fetch_unspent_outputs(address, nodes, offset, limit)}}
          end

        {_, {utxos, false, _}} ->
          {utxos, :eof}

        :eof ->
          {:halt, nil}
      end,
      fn _ -> :ok end
    )
  end

  defp do_fetch_unspent_outputs(address, nodes, offset, limit)

  defp do_fetch_unspent_outputs(address, nodes, offset, limit) do
    conflict_resolver = fn results ->
      %UnspentOutputList{last_chain_sync_date: highest_date} =
        Enum.max_by(results, & &1.last_chain_sync_date, DateTime)

      synced_results = Enum.filter(results, &(&1.last_chain_sync_date == highest_date))

      merged_utxos =
        synced_results
        |> Enum.flat_map(& &1.unspent_outputs)
        |> Enum.uniq()
        |> Enum.sort({:desc, VersionedUnspentOutput})

      offset =
        if Enum.empty?(merged_utxos),
          do: nil,
          else: merged_utxos |> List.last() |> VersionedUnspentOutput.hash()

      %UnspentOutputList{
        unspent_outputs: merged_utxos,
        more?: Enum.any?(synced_results, & &1.more?),
        last_chain_sync_date: highest_date,
        offset: offset
      }
    end

    case P2P.quorum_read(
           nodes,
           %GetUnspentOutputs{address: address, offset: offset, limit: limit},
           conflict_resolver
         ) do
      {:ok,
       %UnspentOutputList{
         unspent_outputs: versioned_unspent_outputs,
         more?: more?,
         offset: offset
       }} ->
        {versioned_unspent_outputs, more?, offset}

      {:error, :network_issue} ->
        {[], false, nil}
    end
  end

  @doc """
  Fetch the transaction chain length for a transaction address

  The result is returned in the shape of `{:ok, length}`.
  If no nodes are able to answer the request, `{:error, :network_issue}` is returned.
  """
  @spec fetch_size(address :: Crypto.prepended_hash(), storage_nodes :: list(Node.t())) ::
          {:ok, non_neg_integer()} | {:error, :network_issue}
  def fetch_size(_, []), do: {:ok, 0}

  def fetch_size(address, nodes) do
    conflict_resolver = fn results ->
      Enum.max_by(results, & &1.length)
    end

    case P2P.quorum_read(
           nodes,
           %GetTransactionChainLength{address: address},
           conflict_resolver
         ) do
      {:ok, %TransactionChainLength{length: length}} ->
        {:ok, length}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  @doc """
  Retrieve the genesis address for a chain from P2P Quorom
  It queries the the network for genesis address.
  """
  @spec fetch_genesis_address(address :: binary(), list(Node.t())) ::
          {:ok, binary()} | {:error, :network_issue}
  def fetch_genesis_address(address, nodes) when is_binary(address) do
    case find_genesis_address(address) do
      {:error, :not_found} ->
        conflict_resolver = fn results ->
          Enum.min_by(results, & &1.timestamp, DateTime)
        end

        case P2P.quorum_read(nodes, %GetGenesisAddress{address: address}, conflict_resolver) do
          {:ok, %GenesisAddress{address: genesis_address}} ->
            {:ok, genesis_address}

          _ ->
            {:error, :network_issue}
        end

      res ->
        res
    end
  end

  @doc """
  Retrieve the First transaction address for a chain from P2P Quorom
  """
  @spec fetch_first_transaction_address(
          address :: binary(),
          storage_nodes :: list(Node.t())
        ) ::
          {:ok, binary()} | {:error, :network_issue} | {:error, :does_not_exist}
  def fetch_first_transaction_address(address, nodes)
      when is_binary(address) and is_list(nodes) do
    case get_first_transaction_address(address) do
      {:ok, {first_address, _}} ->
        {:ok, first_address}

      _ ->
        do_fetch_first_transaction_address(address, nodes)
    end
  end

  defp do_fetch_first_transaction_address(address, nodes) do
    conflict_resolver = fn results ->
      case results |> Enum.reject(&match?(%NotFound{}, &1)) do
        [] ->
          %NotFound{}

        results_filtered ->
          Enum.min_by(results_filtered, & &1.timestamp, DateTime)
      end
    end

    case get_first_transaction_address(address) do
      {:ok, {first_address, _}} ->
        {:ok, first_address}

      _ ->
        case P2P.quorum_read(
               nodes,
               %GetFirstTransactionAddress{address: address},
               conflict_resolver
             ) do
          {:ok, %NotFound{}} ->
            {:error, :does_not_exist}

          {:ok, %FirstTransactionAddress{address: first_address}} ->
            {:ok, first_address}

          _ ->
            {:error, :network_issue}
        end
    end
  end

  # ------------------------------------------------------------
  #   _   _ _____ ___ _     ____
  #  | | | |_   _|_ _| |   / ___|
  #  | | | | | |  | || |   \___ \
  #  | |_| | | |  | || |___ ___) |
  #   \___/  |_| |___|_____|____/
  # ------------------------------------------------------------

  @doc """
  Resolve all the genesis addresses from the transaction data

  **This function raises if it cannot fetch a genesis**
  """
  @spec resolve_transaction_addresses!(transaction :: Transaction.t()) ::
          %{
            (recipient_address :: Crypto.prepended_hash()) =>
              genesis_address :: Crypto.prepended_hash()
          }
  def resolve_transaction_addresses!(
        tx = %Transaction{
          type: type,
          address: address,
          data: %TransactionData{recipients: recipients}
        }
      ) do
    burning_address = LedgerOperations.burning_address()

    recipient_addresses = Enum.map(recipients, & &1.address)

    addresses =
      tx
      |> Transaction.get_movements()
      |> Enum.map(& &1.to)
      |> Enum.concat(recipient_addresses)
      |> Enum.uniq()

    authorized_nodes = P2P.authorized_and_available_nodes()

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      addresses,
      fn
        ^burning_address ->
          {burning_address, burning_address}

        to ->
          case fetch_genesis_address(to, Election.chain_storage_nodes(to, authorized_nodes)) do
            {:ok, genesis} ->
              {to, genesis}

            {:error, :network_issue} ->
              Logger.error("Could not resolve movement address: #{Base.encode16(to)}",
                transaction_address: Base.encode16(address),
                transaction_type: type
              )

              raise "Could not resolve movement address"
          end
      end,
      max_concurrency: 20,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:exit, {%RuntimeError{message: msg}, _stack}} ->
        # bubble up the error
        raise msg

      {:ok, res} ->
        res
    end)
    |> Enum.into(%{})
  end

  @doc """
  Resolve the paging address using requested paging address or from date
  """
  @spec resolve_paging_state(
          last_chain_address :: Crypto.prepended_hash(),
          paging_state :: Crypto.prepended_hash() | DateTime.t() | nil,
          order :: :asc | :desc
        ) ::
          {:ok, paging_address :: Crypto.prepended_hash() | nil}
          | {:error, :not_exists}
          | {:error, :not_in_local}
  def resolve_paging_state(_, nil, _), do: {:ok, nil}

  def resolve_paging_state(_, paging_state, _) when is_binary(paging_state),
    do: {:ok, paging_state}

  def resolve_paging_state(last_chain_address, paging_state = %DateTime{}, order) do
    genesis_address = get_genesis_address(last_chain_address)

    if genesis_address != last_chain_address,
      do: do_resolve_paging_state(genesis_address, paging_state, order),
      else: {:error, :not_in_local}
  end

  defp do_resolve_paging_state(genesis_address, from, :asc) do
    # list_chain_addresses is already sorted by date in asc order
    genesis_address
    |> list_chain_addresses()
    |> Enum.reduce_while(
      %{res: {:error, :not_exists}, previous_address: nil},
      fn {address, date}, acc = %{previous_address: previous_address} ->
        if DateTime.compare(date, from) != :lt,
          do: {:halt, Map.put(acc, :res, {:ok, previous_address})},
          else: {:cont, Map.put(acc, :previous_address, address)}
      end
    )
    |> Map.get(:res)
  end

  defp do_resolve_paging_state(genesis_address, from, :desc) do
    chain_addresses = list_chain_addresses(genesis_address)
    {_, first_date} = Enum.at(chain_addresses, 0)

    if first_date |> DateTime.truncate(:second) |> DateTime.compare(from) == :gt do
      {:error, :not_exists}
    else
      Enum.find_value(chain_addresses, {:ok, nil}, fn {address, date} ->
        if date |> DateTime.truncate(:second) |> DateTime.compare(from) == :gt,
          do: {:ok, address},
          else: nil
      end)
    end
  end

  @doc """
  Register a last address from a genesis address at a given date
  """
  @spec register_last_address(
          genesis_address :: binary(),
          next_address :: binary(),
          timestamp :: DateTime.t()
        ) :: :ok
  defdelegate register_last_address(genesis_address, next_address, timestamp),
    to: DB,
    as: :add_last_transaction_address

  @doc """
  Persist only one transaction
  """
  @spec write_transaction(transaction :: Transaction.t(), storage_location :: DB.storage_type()) ::
          :ok
  def write_transaction(
        tx = %Transaction{
          address: address,
          type: type
        },
        storage_type \\ :chain
      ) do
    DB.write_transaction(tx, storage_type)
    KOLedger.remove_transaction(address)

    Logger.info("Transaction stored",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )
  end

  @doc """
  Write an invalid transaction
  """
  @spec write_ko_transaction(transaction :: Transaction.t(), errors :: list()) :: :ok
  defdelegate write_ko_transaction(tx, additional_errors \\ []),
    to: KOLedger,
    as: :add_transaction

  @doc """
  Determine if the transaction already be validated and is invalid
  """
  @spec transaction_ko?(address :: binary()) :: boolean()
  defdelegate transaction_ko?(address), to: KOLedger, as: :has_transaction?

  @doc """
  Determine if a transaction address has already sent a counter signature (approval) to another transaction
  """
  @spec pending_transaction_signed_by?(to :: binary(), from :: binary()) :: boolean()
  defdelegate pending_transaction_signed_by?(to, from), to: PendingLedger, as: :already_signed?

  @doc """
  Clear the transactions stored as pending
  """
  @spec clear_pending_transactions(address :: binary()) :: :ok
  defdelegate clear_pending_transactions(address), to: PendingLedger, as: :remove_address

  @doc """
  Get the number of transactions for a given type
  """
  @spec count_transactions_by_type(type :: Transaction.transaction_type()) :: non_neg_integer()
  defdelegate count_transactions_by_type(type), to: DB

  @doc """
  Determine if the transaction exists locally
  """
  @spec transaction_exists?(Crypto.prepended_hash(), DB.storage_type()) :: boolean()
  defdelegate transaction_exists?(address, storage_type \\ :chain), to: DB

  @doc """
  Determine if the transaction exists on the locally or in the network
  """
  @spec transaction_exists_globally?(
          address :: Crypto.prepended_hash(),
          storage_nodes :: list(Node.t())
        ) :: boolean()
  def transaction_exists_globally?(address, nodes) do
    if transaction_exists?(address) do
      true
    else
      conflict_resolver = fn results ->
        # Prioritize transactions results over not found
        case Enum.filter(results, &match?(%TransactionSummaryMessage{}, &1)) do
          [] ->
            %NotFound{}

          res ->
            Enum.sort_by(res, & &1.transaction_summary.timestamp, {:desc, DateTime})
            |> List.first()
        end
      end

      case P2P.quorum_read(nodes, %GetTransactionSummary{address: address}, conflict_resolver) do
        {:ok,
         %TransactionSummaryMessage{transaction_summary: %TransactionSummary{address: ^address}}} ->
          true

        _ ->
          false
      end
    end
  end

  @doc """
  Produce a proof of integrity for a given chain.

  If the chain contains only a transaction the hash of the pending is transaction is returned
  Otherwise the hash of the pending transaction and the previous proof of integrity are hashed together

  ## Examples

    With only one transaction

      iex> tx = %Transaction{
      ...>   address:
      ...>     <<0, 0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118,
      ...>       74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>,
      ...>   type: :transfer,
      ...>   data: %TransactionData{},
      ...>   previous_public_key:
      ...>     <<0, 0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8,
      ...>       130, 22, 212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>>,
      ...>   previous_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>,
      ...>   origin_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>
      ...> }
      ...> 
      ...> TransactionChain.proof_of_integrity([tx])
      tx
      |> Transaction.to_pending()
      |> Transaction.serialize()
      |> Crypto.hash()

    With multiple transactions

      iex> tx2 = %Transaction{
      ...>   address:
      ...>     <<0, 0, 61, 7, 130, 64, 140, 226, 192, 8, 238, 88, 226, 106, 137, 45, 69, 113, 239,
      ...>       240, 45, 55, 225, 169, 170, 121, 238, 136, 192, 161, 252, 33, 71, 3>>,
      ...>   type: :transfer,
      ...>   data: %TransactionData{},
      ...>   previous_public_key:
      ...>     <<0, 0, 96, 233, 188, 240, 217, 251, 22, 2, 210, 59, 170, 25, 33, 61, 124, 135, 138,
      ...>       65, 189, 207, 253, 84, 254, 193, 42, 130, 170, 159, 34, 72, 52, 162>>,
      ...>   previous_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>,
      ...>   origin_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>
      ...> }
      ...> 
      ...> tx1 = %Transaction{
      ...>   address:
      ...>     <<0, 0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118,
      ...>       74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>,
      ...>   type: :transfer,
      ...>   data: %TransactionData{},
      ...>   previous_public_key:
      ...>     <<0, 0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8,
      ...>       130, 22, 212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>>,
      ...>   previous_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>,
      ...>   origin_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>,
      ...>   validation_stamp: %ValidationStamp{
      ...>     proof_of_integrity:
      ...>       <<0, 25, 23, 234, 157, 43, 41, 235, 17, 96, 140, 19, 255, 72, 190, 165, 57, 199,
      ...>         167, 167, 195, 8, 59, 230, 229, 246, 12, 191, 68, 203, 99, 11, 176>>
      ...>   }
      ...> }
      ...> 
      ...> TransactionChain.proof_of_integrity([tx2, tx1])
      [
        TransactionChain.proof_of_integrity([tx2]),
        tx1.validation_stamp.proof_of_integrity
      ]
      |> Crypto.hash()
  """
  @spec proof_of_integrity(nonempty_list(Transaction.t())) :: binary()
  def proof_of_integrity([
        tx = %Transaction{}
        | [%Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: previous_poi}} | _]
      ]) do
    Crypto.hash([proof_of_integrity([tx]), previous_poi])
  end

  def proof_of_integrity([tx = %Transaction{} | _]) do
    tx
    |> Transaction.to_pending()
    |> Transaction.serialize(:extended)
    |> Crypto.hash()
  end

  @doc """
  Determines if a chain is valid according to :
  - the proof of integrity
  - the chained public keys and addresses
  - the timestamping

  ## Examples

      iex> tx2 = %Transaction{
      ...>   address:
      ...>     <<0, 0, 61, 7, 130, 64, 140, 226, 192, 8, 238, 88, 226, 106, 137, 45, 69, 113, 239,
      ...>       240, 45, 55, 225, 169, 170, 121, 238, 136, 192, 161, 252, 33, 71, 3>>,
      ...>   type: :transfer,
      ...>   data: %TransactionData{},
      ...>   previous_public_key:
      ...>     <<0, 0, 96, 233, 188, 240, 217, 251, 22, 2, 210, 59, 170, 25, 33, 61, 124, 135, 138,
      ...>       65, 189, 207, 253, 84, 254, 193, 42, 130, 170, 159, 34, 72, 52, 162>>,
      ...>   previous_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>,
      ...>   origin_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>
      ...> }
      ...> 
      ...> tx1 = %Transaction{
      ...>   address:
      ...>     <<0, 0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118,
      ...>       74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>,
      ...>   type: :transfer,
      ...>   data: %TransactionData{},
      ...>   previous_public_key:
      ...>     <<0, 0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8,
      ...>       130, 22, 212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>>,
      ...>   previous_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>,
      ...>   origin_signature:
      ...>     <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216,
      ...>       215, 255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212,
      ...>       227, 167, 161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165,
      ...>       197, 25, 219, 84, 232, 135, 42, 112, 58, 181, 13>>
      ...> }
      ...> 
      ...> tx1 = %{
      ...>   tx1
      ...>   | validation_stamp: %ValidationStamp{
      ...>       proof_of_integrity: TransactionChain.proof_of_integrity([tx1]),
      ...>       timestamp: ~U[2022-09-10 10:00:00Z]
      ...>     }
      ...> }
      ...> 
      ...> tx2 = %{
      ...>   tx2
      ...>   | validation_stamp: %ValidationStamp{
      ...>       proof_of_integrity: TransactionChain.proof_of_integrity([tx2, tx1]),
      ...>       timestamp: ~U[2022-12-10 10:00:00Z]
      ...>     }
      ...> }
      ...> 
      ...> TransactionChain.valid?([tx2, tx1])
      true

  """
  @spec valid?([Transaction.t(), ...]) :: boolean
  def valid?([
        tx = %Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: poi}},
        nil
      ]) do
    if poi == proof_of_integrity([tx]) do
      true
    else
      Logger.error("Invalid proof of integrity",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      false
    end
  end

  def valid?([
        last_tx = %Transaction{
          previous_public_key: previous_public_key,
          validation_stamp: %ValidationStamp{timestamp: timestamp, proof_of_integrity: poi}
        },
        prev_tx = %Transaction{
          address: previous_address,
          validation_stamp: %ValidationStamp{
            timestamp: previous_timestamp
          }
        }
        | _
      ]) do
    cond do
      proof_of_integrity([Transaction.to_pending(last_tx), prev_tx]) != poi ->
        Logger.error("Invalid proof of integrity",
          transaction_address: Base.encode16(last_tx.address),
          transaction_type: last_tx.type
        )

        false

      Crypto.derive_address(previous_public_key) != previous_address ->
        Logger.error("Invalid previous public key",
          transaction_type: last_tx.type,
          transaction_address: Base.encode16(last_tx.address)
        )

        false

      DateTime.diff(timestamp, previous_timestamp) < 0 ->
        Logger.error("Invalid timestamp",
          transaction_type: last_tx.type,
          transaction_address: Base.encode16(last_tx.address)
        )

        false

      true ->
        true
    end
  end

  # @doc """
  # Load the transaction into the TransactionChain context filling the memory tables
  # """
  # @spec load_transaction(Transaction.t()) :: :ok
  # defdelegate load_transaction(tx), to: MemTablesLoader

  @doc """
  Return the list inputs for a given transaction
  """
  @spec get_inputs(address :: binary()) :: Enumerable.t() | list(VersionedTransactionInput.t())
  defdelegate get_inputs(adddress), to: DBLedger, as: :stream_inputs

  @doc """
  Write the validation's input for a given transaction
  """
  @spec write_inputs(address :: binary(), inputs :: list(VersionedTransactionInput.t())) :: :ok
  defdelegate write_inputs(address, inputs), to: DBLedger

  @doc """
  Return the list of addresses after the given address
  """
  @spec get_next_addresses(address :: binary(), limit :: non_neg_integer()) ::
          list({address :: binary(), timestamp :: DateTime.t()})
  def get_next_addresses(address, limit \\ 0) do
    case get_transaction(address, validation_stamp: [:timestamp]) do
      {:ok, %Transaction{validation_stamp: %ValidationStamp{timestamp: address_timestamp}}} ->
        addresses =
          address
          |> get_genesis_address()
          |> list_chain_addresses()
          |> Enum.filter(fn {_address, timestamp} ->
            DateTime.compare(timestamp, address_timestamp) == :gt
          end)

        if limit > 0 do
          Enum.take(addresses, limit)
        else
          addresses
        end

      _ ->
        []
    end
  end
end
