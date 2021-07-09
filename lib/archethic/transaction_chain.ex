defmodule ArchEthic.TransactionChain do
  @moduledoc """
  Handle the logic managing transaction chain
  """

  alias ArchEthic.Crypto

  alias ArchEthic.DB

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message
  alias ArchEthic.P2P.Message.GetLastTransactionAddress
  alias ArchEthic.P2P.Message.LastTransactionAddress

  alias ArchEthic.Replication

  alias __MODULE__.MemTables.KOLedger
  alias __MODULE__.MemTables.PendingLedger
  alias __MODULE__.MemTablesLoader

  alias __MODULE__.Transaction
  alias __MODULE__.Transaction.ValidationStamp

  alias ArchEthic.Utils

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
  @spec get(binary(), list()) :: list(Transaction.t())
  defdelegate get(address, fields \\ []), to: DB, as: :get_transaction_chain

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

  def write_transaction(tx = %Transaction{address: address, type: type}, chain_address) do
    DB.write_transaction(tx, chain_address)
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
  Produce a proof of integrity for a given chain.

  If the chain contains only a transaction the hash of the pending is transaction is returned
  Otherwise the hash of the pending transaction and the previous proof of integrity are hashed together

  ## Examples

    With only one transaction

      iex> [
      ...>    %Transaction{
      ...>      address: <<0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118, 74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>, 
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
      <<0, 168, 253, 68, 23, 3, 170, 98, 176, 44, 251, 175, 84, 56, 161, 147, 29, 88, 164, 4, 252, 142, 121, 184, 231, 12, 120, 218, 254, 0, 22, 4, 248>>

    With multiple transactions

      iex> [
      ...>   %Transaction{
      ...>     address:
      ...>       <<61, 7, 130, 64, 140, 226, 192, 8, 238, 88, 226, 106, 137, 45, 69, 113, 239,
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
      ...>      address: <<0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118, 74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>, 
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
      ...>         proof_of_integrity: <<0, 168, 253, 68, 23, 3, 170, 98, 176, 44, 251, 175, 84, 56, 161, 147, 29, 88, 164, 4, 252, 142, 121, 184, 231, 12, 120, 218, 254, 0, 22, 4, 248>>
      ...>      }
      ...>    }
      ...> ]
      ...> |> TransactionChain.proof_of_integrity()  
      # Hash of the transaction + previous proof of integrity
      <<0, 104, 137, 45, 231, 228, 218, 226, 222, 107, 70, 82, 114, 175, 125, 175, 67, 255, 70, 164, 89, 145, 130, 219, 69, 145, 88, 245, 160, 243, 195, 127, 70>> 
  """
  @spec proof_of_integrity(nonempty_list(Transaction.t())) :: binary()
  def proof_of_integrity([
        tx = %Transaction{}
        | [%Transaction{validation_stamp: %ValidationStamp{proof_of_integrity: previous_poi}}]
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
      ...>       <<61, 7, 130, 64, 140, 226, 192, 8, 238, 88, 226, 106, 137, 45, 69, 113, 239,
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
      ...>        proof_of_integrity: <<0, 104, 137, 45, 231, 228, 218, 226, 222, 107, 70, 82, 114, 175, 125, 175, 67, 255, 70, 164, 89, 145, 130, 219, 69, 145, 88, 245, 160, 243, 195, 127, 70>> 
      ...>      }
      ...>    },
      ...>    %Transaction{
      ...>      address: <<0, 109, 140, 2, 60, 50, 109, 201, 126, 206, 164, 10, 86, 225, 58, 136, 241, 118, 74, 3, 215, 6, 106, 165, 24, 51, 192, 212, 58, 143, 33, 68, 2>>,
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
      ...>         proof_of_integrity: <<0, 168, 253, 68, 23, 3, 170, 98, 176, 44, 251, 175, 84, 56, 161, 147, 29, 88, 164, 4, 252, 142, 121, 184, 231, 12, 120, 218, 254, 0, 22, 4, 248>>
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

      Crypto.hash(previous_public_key) != previous_address ->
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
  Retrieve the last address of a chain
  """
  @spec resolve_last_address(binary(), DateTime.t()) :: binary()
  def resolve_last_address(address, timestamp = %DateTime{}) when is_binary(address) do
    message = %GetLastTransactionAddress{address: address, timestamp: timestamp}

    storage_nodes = Replication.chain_storage_nodes(address)

    if Utils.key_in_node_list?(storage_nodes, Crypto.first_node_public_key()) do
      handle_resolve_result({:ok, Message.process(message)}, address)
    else
      storage_nodes
      |> P2P.reply_first(message)
      |> handle_resolve_result(address)
    end
  end

  defp handle_resolve_result({:ok, %LastTransactionAddress{address: last_address}}, _),
    do: last_address

  defp handle_resolve_result(_, address), do: address
end
