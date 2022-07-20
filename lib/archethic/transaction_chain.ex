defmodule Archethic.TransactionChain do
  @moduledoc """
  Handle the logic managing transaction chain
  """

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Error

  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.FirstAddress

  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetFirstAddress
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetTransactionChainLength

  alias __MODULE__.MemTables.KOLedger
  alias __MODULE__.MemTables.PendingLedger
  alias __MODULE__.MemTablesLoader

  alias Archethic.TaskSupervisor

  alias __MODULE__.Transaction
  alias __MODULE__.TransactionData
  alias __MODULE__.Transaction.ValidationStamp
  alias __MODULE__.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias __MODULE__.TransactionSummary
  alias __MODULE__.TransactionInput

  require Logger

  @doc """
  List all the transaction chain stored
  """
  @spec list_all(fields :: list()) :: Enumerable.t()
  defdelegate list_all(fields \\ []), to: DB, as: :list_transactions

  @doc """
  List all the transaction for a given transaction type sorted by timestamp in descent order
  """
  @spec list_transactions_by_type(type :: Transaction.transaction_type(), fields :: list()) ::
          Enumerable.t()
  defdelegate list_transactions_by_type(type, fields), to: DB

  @doc """
  Get the number of transactions for a given type
  """
  @spec count_transactions_by_type(type :: Transaction.transaction_type()) :: non_neg_integer()
  defdelegate count_transactions_by_type(type), to: DB

  @doc """
  Stream all the addresses for a transaction type
  """
  @spec list_addresses_by_type(Transaction.transaction_type()) :: Enumerable.t() | list(binary())
  defdelegate list_addresses_by_type(type), to: DB

  @doc """
  Get the last transaction address from a transaction chain
  """
  @spec get_last_address(binary()) :: binary()
  defdelegate get_last_address(address),
    to: DB,
    as: :get_last_chain_address

  @doc """
  Get the last transaction address from a transaction chain before a given date
  """
  @spec get_last_address(binary(), DateTime.t()) :: binary()
  defdelegate get_last_address(address, timestamp),
    to: DB,
    as: :get_last_chain_address

  @doc """
  Register a last address from a previous address at a given date
  """
  @spec register_last_address(binary(), binary(), DateTime.t()) :: :ok
  defdelegate register_last_address(previous_address, next_address, timestamp),
    to: DB,
    as: :add_last_transaction_address

  @doc """
  Get the first public key from one the public key of the chain
  """
  @spec get_first_public_key(Crypto.key()) :: Crypto.key()
  defdelegate get_first_public_key(previous_public_key), to: DB, as: :get_first_public_key

  @doc """
  Get a transaction

  A lookup is performed into the KO ledger to determine if the transaction is invalid
  """
  @spec get_transaction(binary(), fields :: list()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :invalid_transaction}
  def get_transaction(address, fields \\ []) when is_list(fields) do
    if KOLedger.has_transaction?(address) do
      {:error, :invalid_transaction}
    else
      DB.get_transaction(address, fields)
    end
  end

  @doc """
  Retrieve an entire chain from the last transaction
  The returned list is ordered chronologically.
  """
  @spec get(binary(), list()) ::
          Enumerable.t() | {list(Transaction.t()), boolean(), binary()}
  defdelegate get(address, fields \\ [], opts \\ []), to: DB, as: :get_transaction_chain

  @doc """
  Persist only one transaction
  """
  @spec write_transaction(Transaction.t()) :: :ok
  def write_transaction(
        tx = %Transaction{
          address: address,
          type: type
        }
      ) do
    DB.write_transaction(tx)
    KOLedger.remove_transaction(address)

    Logger.info("Transaction stored",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )
  end

  @doc """
  Write the transaction in a specific genesis address
  """
  @spec write_transaction_at(Transaction.t(), binary()) :: :ok
  def write_transaction_at(tx = %Transaction{address: address, type: type}, genesis_address) do
    DB.write_transaction_at(tx, genesis_address)
    KOLedger.remove_transaction(address)

    Logger.info("Transaction stored",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )
  end

  @doc """
  Persist a new transaction chain
  """
  @spec write(Enumerable.t()) :: :ok
  def write(chain) do
    sorted_chain = Enum.sort_by(chain, & &1.validation_stamp.timestamp, {:desc, DateTime})

    %Transaction{
      address: tx_address,
      type: tx_type
    } = Enum.at(sorted_chain, 0)

    DB.write_transaction_chain(sorted_chain)
    KOLedger.remove_transaction(tx_address)

    Logger.info("Transaction Chain stored",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )
  end

  @doc """
  Write an invalid transaction
  """
  @spec write_ko_transaction(Transaction.t(), list()) :: :ok
  defdelegate write_ko_transaction(tx, additional_errors \\ []),
    to: KOLedger,
    as: :add_transaction

  @doc """
  Determine if the transaction already be validated and is invalid
  """
  @spec transaction_ko?(binary()) :: boolean()
  defdelegate transaction_ko?(address), to: KOLedger, as: :has_transaction?

  @doc """
  Get the details from a ko transaction address
  """
  @spec get_ko_details(binary()) ::
          {ValidationStamp.t(), inconsistencies :: list(), errors :: list()}
  defdelegate get_ko_details(address), to: KOLedger, as: :get_details

  @doc """
  List of all the counter signatures regarding a given transaction
  """
  @spec list_signatures_for_pending_transaction(binary()) :: list(binary())
  defdelegate list_signatures_for_pending_transaction(address),
    to: PendingLedger,
    as: :list_signatures

  @doc """
  Determine if a transaction address has already sent a counter signature (approval) to another transaction
  """
  @spec pending_transaction_signed_by?(to :: binary(), from :: binary()) :: boolean()
  defdelegate pending_transaction_signed_by?(to, from), to: PendingLedger, as: :already_signed?

  @doc """
  Determine if the transaction exists
  """
  @spec transaction_exists?(binary()) :: boolean()
  defdelegate transaction_exists?(address), to: DB

  @doc """
  Return the size of transaction chain
  """
  @spec size(binary()) :: non_neg_integer()
  defdelegate size(address), to: DB, as: :chain_size

  @doc """
  Get the last transaction from a given chain address
  """
  @spec get_last_transaction(binary(), list()) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :invalid_transaction}
  def get_last_transaction(address, fields \\ []) when is_binary(address) and is_list(fields) do
    address
    |> get_last_address()
    |> get_transaction(fields)
  end

  @doc """
  Get the first transaction from a given chain address
  """
  @spec get_first_transaction(binary(), list()) ::
          {:ok, Transaction.t()} | {:error, :transaction_not_exists}
  def get_first_transaction(address, fields \\ []) when is_binary(address) do
    address
    |> DB.get_first_chain_address()
    |> get_transaction(fields)
  end

  @doc """
  Get the genesis address from a given chain address
  """
  @spec get_genesis_address(binary()) :: binary()
  defdelegate get_genesis_address(address), to: DB, as: :get_first_chain_address

  @doc """
  Produce a proof of integrity for a given chain.

  If the chain contains only a transaction the hash of the pending is transaction is returned
  Otherwise the hash of the pending transaction and the previous proof of integrity are hashed together

  ## Examples

    With only one transaction

      iex> [
      ...>    %Transaction{
      ...>      address: <<0, 0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118, 74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>,
      ...>      type: :transfer,
      ...>      data: %TransactionData{},
      ...>      previous_public_key:
      ...>        <<0, 0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8, 130, 22,
      ...>        212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>>,
      ...>      previous_signature:
      ...>        <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>        255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>        161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>        232, 135, 42, 112, 58, 181, 13>>,
      ...>      origin_signature:
      ...>        <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>        255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>        161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>        232, 135, 42, 112, 58, 181, 13>>
      ...>    }
      ...>  ]
      ...>  |> TransactionChain.proof_of_integrity()
      # Hash of the transaction
      <<0, 123, 128, 98, 182, 113, 165, 184, 172, 49, 237, 243, 192, 225, 204, 187, 160, 160, 64, 117, 136, 51, 186, 226, 34, 145, 31, 69, 48, 34, 164, 253, 95>>

    With multiple transactions

      iex> [
      ...>   %Transaction{
      ...>     address:
      ...>       <<0, 0, 61, 7, 130, 64, 140, 226, 192, 8, 238, 88, 226, 106, 137, 45, 69, 113, 239,
      ...>         240, 45, 55, 225, 169, 170, 121, 238, 136, 192, 161, 252, 33, 71, 3>>,
      ...>     type: :transfer,
      ...>     data: %TransactionData{},
      ...>     previous_public_key:
      ...>       <<0, 0, 96, 233, 188, 240, 217, 251, 22, 2, 210, 59, 170, 25, 33, 61, 124, 135,
      ...>         138, 65, 189, 207, 253, 84, 254, 193, 42, 130, 170, 159, 34, 72, 52, 162>>,
      ...>     previous_signature:
      ...>       <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>       255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>       161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>       232, 135, 42, 112, 58, 181, 13>>,
      ...>     origin_signature:
      ...>       <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>       255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>       161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>       232, 135, 42, 112, 58, 181, 13>>
      ...>    },
      ...>    %Transaction{
      ...>      address: <<0, 0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118, 74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>,
      ...>      type: :transfer,
      ...>      data: %TransactionData{},
      ...>      previous_public_key:
      ...>        <<0, 0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8, 130, 22,
      ...>        212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>>,
      ...>      previous_signature:
      ...>        <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>        255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>        161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>        232, 135, 42, 112, 58, 181, 13>>,
      ...>      origin_signature:
      ...>        <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>        255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>        161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>        232, 135, 42, 112, 58, 181, 13>>,
      ...>      validation_stamp: %ValidationStamp{
      ...>         proof_of_integrity: <<0, 123, 128, 98, 182, 113, 165, 184, 172, 49, 237, 243, 192, 225, 204, 187,
      ...>           160, 160, 64, 117, 136, 51, 186, 226, 34, 145, 31, 69, 48, 34, 164, 253, 95>>
      ...>      }
      ...>    }
      ...> ]
      ...> |> TransactionChain.proof_of_integrity()
      # Hash of the transaction + previous proof of integrity
      <<0, 150, 171, 173, 84, 39, 116, 164, 116, 216, 112, 168, 253, 154, 141, 95,
        123, 179, 96, 253, 195, 247, 192, 75, 47, 173, 144, 82, 99, 4, 10, 149, 169>>
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
    |> Transaction.serialize()
    |> Crypto.hash()
  end

  @doc """
  Determines if a chain is valid according to :
  - the proof of integrity
  - the chained public keys and addresses
  - the timestamping

  ## Examples

      iex> [
      ...>   %Transaction{
      ...>     address:
      ...>       <<0, 0, 61, 7, 130, 64, 140, 226, 192, 8, 238, 88, 226, 106, 137, 45, 69, 113, 239,
      ...>         240, 45, 55, 225, 169, 170, 121, 238, 136, 192, 161, 252, 33, 71, 3>>,
      ...>     type: :transfer,
      ...>     data: %TransactionData{},
      ...>     previous_public_key:
      ...>       <<0, 0, 96, 233, 188, 240, 217, 251, 22, 2, 210, 59, 170, 25, 33, 61, 124, 135,
      ...>         138, 65, 189, 207, 253, 84, 254, 193, 42, 130, 170, 159, 34, 72, 52, 162>>,
      ...>     previous_signature:
      ...>       <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>         255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>         161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>         232, 135, 42, 112, 58, 181, 13>>,
      ...>     origin_signature:
      ...>       <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>         255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>         161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>         232, 135, 42, 112, 58, 181, 13>>,
      ...>     validation_stamp: %ValidationStamp{
      ...>        timestamp: ~U[2020-03-30 12:06:30.000Z],
      ...>        proof_of_integrity: <<0, 150, 171, 173, 84, 39, 116, 164, 116, 216, 112, 168, 253, 154, 141, 95,
      ...>          123, 179, 96, 253, 195, 247, 192, 75, 47, 173, 144, 82, 99, 4, 10, 149, 169>>
      ...>      }
      ...>    },
      ...>    %Transaction{
      ...>      address: <<0, 0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118, 74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>,
      ...>      type: :transfer,
      ...>      data: %TransactionData{},
      ...>      previous_public_key:
      ...>        <<0, 0, 221, 228, 196, 111, 16, 222, 0, 119, 32, 150, 228, 25, 206, 79, 37, 213, 8, 130, 22,
      ...>        212, 99, 55, 72, 11, 248, 250, 11, 140, 137, 167, 118, 253>>,
      ...>      previous_signature:
      ...>        <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>          255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>          161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>          232, 135, 42, 112, 58, 181, 13>>,
      ...>      origin_signature:
      ...>        <<232, 186, 237, 220, 71, 212, 177, 17, 156, 167, 145, 125, 92, 70, 213, 120, 216, 215,
      ...>          255, 158, 104, 117, 162, 18, 142, 75, 73, 205, 71, 7, 141, 90, 178, 239, 212, 227, 167,
      ...>          161, 155, 143, 43, 50, 6, 7, 97, 130, 134, 174, 7, 235, 183, 88, 165, 197, 25, 219, 84,
      ...>          232, 135, 42, 112, 58, 181, 13>>,
      ...>      validation_stamp: %ValidationStamp{
      ...>         timestamp: ~U[2020-03-30 10:06:30.000Z],
      ...>         proof_of_integrity: <<0, 123, 128, 98, 182, 113, 165, 184, 172, 49, 237, 243, 192, 225, 204, 187, 160, 160, 64, 117, 136, 51, 186, 226, 34, 145, 31, 69, 48, 34, 164, 253, 95>>
      ...>      }
      ...>    }
      ...> ]
      ...> |> TransactionChain.valid?()
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

  @doc """
  Load the transaction into the TransactionChain context filling the memory tables
  """
  @spec load_transaction(Transaction.t()) :: :ok
  defdelegate load_transaction(tx), to: MemTablesLoader

  @doc """
  Resolve all the last addresses from the transaction data
  """
  @spec resolve_transaction_addresses(Transaction.t(), DateTime.t()) ::
          list({origin_address :: binary(), resolved_address :: binary()})
  def resolve_transaction_addresses(
        tx = %Transaction{data: %TransactionData{recipients: recipients}},
        time = %DateTime{}
      ) do
    addresses =
      tx
      |> Transaction.get_movements()
      |> Enum.map(& &1.to)
      |> Enum.concat(recipients)

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      addresses,
      fn to ->
        case resolve_last_address(to, time) do
          {:ok, resolved} ->
            {to, resolved}

          _ ->
            {to, to}
        end
      end,
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, res} -> res end)
  end

  @doc """
  Retrieve the last address of a chain
  """
  @spec resolve_last_address(binary(), DateTime.t()) :: {:ok, binary()} | {:error, :network_issue}
  def resolve_last_address(address, timestamp = %DateTime{} \\ DateTime.utc_now())
      when is_binary(address) do
    nodes =
      address
      |> Election.chain_storage_nodes(P2P.available_nodes())
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    case fetch_last_address_remotely(address, nodes, timestamp) do
      {:ok, last_address} ->
        {:ok, last_address}

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Fetch the last address remotely
  """
  @spec fetch_last_address_remotely(binary(), list(Node.t()), DateTime.t()) ::
          {:ok, binary()} | {:error, :network_issue}
  def fetch_last_address_remotely(address, nodes, timestamp = %DateTime{} \\ DateTime.utc_now())
      when is_binary(address) and is_list(nodes) do
    # TODO: implement conflict resolver to get the latest address
    case P2P.quorum_read(
           nodes,
           %GetLastTransactionAddress{address: address, timestamp: timestamp}
         ) do
      {:ok, %LastTransactionAddress{address: last_address}} ->
        {:ok, last_address}

      {:error, :network_issue} = e ->
        e
    end
  end

  @doc """
  Get a transaction summary from a transaction address
  """
  @spec get_transaction_summary(binary()) :: {:ok, TransactionSummary.t()} | {:error, :not_found}
  def get_transaction_summary(address) do
    case get_transaction(address, [
           :address,
           :type,
           validation_stamp: [
             :timestamp,
             ledger_operations: [:fee, :transaction_movements]
           ]
         ]) do
      {:ok, tx} ->
        {:ok, TransactionSummary.from_transaction(tx)}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Stream the transactions from a chain
  """
  @spec stream(binary(), list()) :: Enumerable.t() | list(Transaction.t())
  def stream(address, fields) do
    Stream.resource(
      fn -> DB.get_transaction_chain(address, fields, []) end,
      fn
        {transactions, true, paging_state} ->
          {transactions, DB.get_transaction_chain(address, fields, paging_state: paging_state)}

        {transactions, false, _} ->
          {transactions, :eof}

        :eof ->
          {:halt, nil}
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Fetch transaction remotely

  If the transaction exists, then its value is returned in the shape of `{:ok, transaction}`.
  If the transaction doesn't exist, `{:error, :transaction_not_exists}` is returned.

  If no nodes are available to answer the request, `{:error, :network_issue}` is returned.
  """
  @spec fetch_transaction_remotely(address :: Crypto.versioned_hash(), list(Node.t())) ::
          {:ok, Transaction.t()}
          | {:error, :transaction_not_exists}
          | {:error, :transaction_invalid}
          | {:error, :network_issue}
  def fetch_transaction_remotely(_, []), do: {:error, :transaction_not_exists}

  def fetch_transaction_remotely(address, nodes) when is_binary(address) and is_list(nodes) do
    conflict_resolver = fn results ->
      # Prioritize transactions results over not found
      with nil <- Enum.find(results, &match?(%Transaction{}, &1)),
           nil <- Enum.find(results, &match?(%Error{}, &1)) do
        %NotFound{}
      else
        res ->
          res
      end
    end

    case P2P.quorum_read(
           nodes,
           %GetTransaction{address: address},
           conflict_resolver
         ) do
      {:ok, %NotFound{}} ->
        {:error, :transaction_not_exists}

      {:ok, %Error{}} ->
        {:error, :transaction_invalid}

      {:ok, tx = %Transaction{}} ->
        {:ok, tx}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  @doc """
  Stream transaction chain remotely
  """
  @spec stream_remotely(
          address :: Crypto.versioned_hash(),
          list(Node.t()),
          paging_state :: nil | binary()
        ) ::
          Enumerable.t() | list(Transaction.t())
  def stream_remotely(address, nodes, paging_state \\ nil)
  def stream_remotely(_, [], _), do: []

  def stream_remotely(address, nodes, paging_state)
      when is_binary(address) and is_list(nodes) do
    Stream.resource(
      fn -> {address, paging_state, 0} end,
      fn
        {:end, _size} ->
          {:halt, address}

        {address, paging_state, size} ->
          do_stream_chain(nodes, address, paging_state, size)
      end,
      fn _ -> :ok end
    )
  end

  defp do_stream_chain(nodes, address, paging_state, size) do
    case fetch_transaction_chain(nodes, address, paging_state) do
      {transactions, false, _} ->
        {[transactions], {:end, size + length(transactions)}}

      {transactions, true, paging_state} ->
        {[transactions], {address, paging_state, size + length(transactions)}}
    end
  end

  defp fetch_transaction_chain(
         nodes,
         address,
         paging_state
       ) do
    conflict_resolver = fn results ->
      results
      |> Enum.sort(
        &((&1.more? and !&2.more?) or length(&1.transactions) > length(&2.transactions))
      )
      |> List.first()
    end

    # Get transaction chain size to calculate timeout
    chain_size =
      case Archethic.get_transaction_chain_length(address) do
        {:ok, chain_size} ->
          chain_size

        _ ->
          1
      end

    timeout = Message.get_max_timeout() + Message.get_max_timeout() * chain_size

    case P2P.quorum_read(
           nodes,
           %GetTransactionChain{address: address, paging_state: paging_state},
           conflict_resolver,
           timeout
         ) do
      {:ok,
       %TransactionList{transactions: transactions, more?: more?, paging_state: paging_state}} ->
        {transactions, more?, paging_state}

      {:error, :network_issue} ->
        raise "Cannot fetch transaction chain"
    end
  end

  @doc """
  Fetch the transaction inputs for a transaction address at a given time

  If the inputs exist, then they are returned in the shape of `{:ok, inputs}`.
  If no nodes are able to answer the request, `{:error, :network_issue}` is returned.
  """
  @spec fetch_inputs_remotely(address :: Crypto.versioned_hash(), list(Node.t()), DateTime.t()) ::
          {:ok, list(TransactionInput.t())} | {:error, :network_issue}
  def fetch_inputs_remotely(_, [], _), do: {:ok, []}

  def fetch_inputs_remotely(address, nodes, timestamp = %DateTime{})
      when is_binary(address) and is_list(nodes) do
    conflict_resolver = fn results ->
      results
      |> Enum.sort_by(&length(&1.inputs), :desc)
      |> List.first()
    end

    case P2P.quorum_read(
           nodes,
           %GetTransactionInputs{address: address},
           conflict_resolver
         ) do
      {:ok, %TransactionInputList{inputs: inputs}} ->
        filtered_inputs = Enum.filter(inputs, &(DateTime.diff(&1.timestamp, timestamp) <= 0))
        {:ok, filtered_inputs}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  @doc """
  Fetch the transaction unspent outputs for a transaction address at a given time

  If the utxo exist, then they are returned in the shape of `{:ok, inputs}`.
  If no nodes are able to answer the request, `{:error, :network_issue}` is returned.
  """
  @spec fetch_unspent_outputs_remotely(
          address :: Crypto.versioned_hash(),
          list(Node.t())
        ) ::
          {:ok, list(UnspentOutput.t())} | {:error, :network_issue}
  def fetch_unspent_outputs_remotely(_, []), do: {:ok, []}

  def fetch_unspent_outputs_remotely(address, nodes)
      when is_binary(address) and is_list(nodes) do
    conflict_resolver = fn results ->
      results
      |> Enum.sort_by(&length(&1.unspent_outputs), :desc)
      |> List.first()
    end

    case P2P.quorum_read(
           nodes,
           %GetUnspentOutputs{address: address},
           conflict_resolver
         ) do
      {:ok, %UnspentOutputList{unspent_outputs: unspent_outputs}} ->
        {:ok, unspent_outputs}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  @doc """
  Fetch the transaction chain length for a transaction address

  The result is returned in the shape of `{:ok, length}`.
  If no nodes are able to answer the request, `{:error, :network_issue}` is returned.
  """
  @spec fetch_size_remotely(Crypto.versioned_hash(), list(Node.t())) ::
          {:ok, non_neg_integer()} | {:error, :network_issue}
  def fetch_size_remotely(_, []), do: {:ok, 0}

  def fetch_size_remotely(address, nodes) do
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
  Retrieve the last transaction address for a chain stored locally
  It queries the the network for genesis address
  """
  @spec get_last_local_address(address :: binary()) :: binary() | nil
  def get_last_local_address(address) when is_binary(address) do
    case fetch_genesis_address_remotely(address) do
      {:ok, genesis_address} ->
        case get_last_address(genesis_address) do
          ^genesis_address -> nil
          last_address -> last_address
        end

      _ ->
        nil
    end
  end

  defp fetch_genesis_address_remotely(address) when is_binary(address) do
    nodes =
      address
      |> Election.chain_storage_nodes(P2P.available_nodes())
      |> P2P.nearest_nodes()
      |> Enum.filter(&Node.locally_available?/1)

    case P2P.quorum_read(nodes, %GetFirstAddress{address: address}) do
      {:ok, %FirstAddress{address: genesis_address}} ->
        {:ok, genesis_address}

      _ ->
        {:error, :network_issue}
    end
  end

  @spec get_locally(address :: binary(), paging_address :: binary() | nil) ::
          Enumerable.t() | list(Transaction.t())
  def get_locally(address, paging_address \\ nil) when is_binary(address) do
    fetch_chain_db(get(address, [], paging_state: paging_address), [])
  end

  def fetch_chain_db({chain, false, _}, acc), do: acc ++ chain

  def fetch_chain_db({chain, true, paging_address}, acc) do
    fetch_chain_db(get(paging_address, [], paging_state: paging_address), acc ++ chain)
  end
end
