defmodule Archethic.SelfRepair.Sync.TransactionHandler do
  @moduledoc false

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.P2P.Message

  alias Archethic.Replication

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

  require Logger

  @doc """
  Determine if the transaction should be downloaded by the local node.

  Verify firstly the chain storage nodes election.
  If not successful, perform storage nodes election based on the transaction movements.
  """
  @spec download_transaction?(ReplicationAttestation.t(), list(Node.t())) :: boolean()
  def download_transaction?(%ReplicationAttestation{
        transaction_summary: %TransactionSummary{
          version: 1
        }
      }),
      do: true

  def download_transaction?(
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: address,
            type: type,
            genesis_address: genesis_address,
            movements_addresses: movements_addresses
          }
        },
        node_list
      ) do
    last_chain_storage_nodes = Election.chain_storage_nodes_with_type(address, type, node_list)
    genesis_chain_storage_nodes = Election.chain_storage_nodes(genesis_address, node_list)
    node_key = Crypto.first_node_public_key()

    last_chain_node? = Utils.key_in_node_list?(last_chain_storage_nodes, node_key)
    genesis_node? = Utils.key_in_node_list?(genesis_chain_storage_nodes, node_key)

    if last_chain_node? do
      not TransactionChain.transaction_exists?(address)
    else
      if TransactionChain.transaction_exists?(address, :io) do
        false
      else
        io_node? =
          movements_addresses
          |> Election.io_storage_nodes(node_list)
          |> Utils.key_in_node_list?(Crypto.first_node_public_key())

        genesis_node? or io_node?
      end
    end
  end

  @doc """
  Download a transaction from closest storage nodes and ensure the transaction
  is the same than the one in the replication attestation
  """
  @spec download_transaction(ReplicationAttestation.t(), list(Node.t())) ::
          Transaction.t()
  def download_transaction(
        %ReplicationAttestation{
          transaction_summary:
            expected_summary = %TransactionSummary{
              version: version,
              address: address,
              type: type,
              genesis_address: genesis_address
            }
        },
        node_list
      ) do
    Logger.info("Synchronize missed transaction",
      transaction_address: Base.encode16(address),
      transaction_type: type
    )

    storage_nodes =
      address
      |> Election.chain_storage_nodes_with_type(type, node_list)
      |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))

    timeout = Message.get_max_timeout()

    acceptance_resolver = fn tx = %Transaction{} ->
      # TODO:
      # we can add a verification to ensure the proof of integrity is the right one
      # using the previous transaction and hence asserting the TransactionSummary.validation_stamp_checksum
      # in order to remove malicious node given false transaction's data

      tx
      |> TransactionSummary.from_transaction(genesis_address, version)
      |> TransactionSummary.equals?(expected_summary)
    end

    case TransactionChain.fetch_transaction(address, storage_nodes,
           search_mode: :remote,
           timeout: timeout,
           acceptance_resolver: acceptance_resolver
         ) do
      {:ok, tx = %Transaction{}} ->
        tx

      {:error, reason} ->
        Logger.error("Cannot fetch the transaction to sync because of #{inspect(reason)}",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        raise "Error downloading transaction"
    end
  end

  @spec process_transaction(ReplicationAttestation.t(), Transaction.t(), list(Node.t())) :: :ok
  def process_transaction(
        attestation = %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            genesis_address: genesis_address,
            movements_addresses: movements_addresses
          }
        },
        tx = %Transaction{
          address: address,
          type: type
        },
        node_list
      ) do
    verify_transaction(attestation, tx)

    node_list = [P2P.get_node_info() | node_list] |> P2P.distinct_nodes()

    last_chain_node? =
      Election.chain_storage_node?(address, type, Crypto.first_node_public_key(), node_list)

    io_movement_node? =
      movements_addresses
      |> Election.io_storage_nodes(node_list)
      |> Utils.key_in_node_list?(Crypto.first_node_public_key())

    genesis_node? =
      Election.chain_storage_node?(genesis_address, Crypto.first_node_public_key(), node_list)

    cond do
      last_chain_node? ->
        Replication.sync_transaction_chain(tx, genesis_address, node_list, self_repair?: true)

      io_movement_node? or genesis_node? ->
        Replication.synchronize_io_transaction(tx, self_repair?: true)

      true ->
        :ok
    end
  end

  defp verify_transaction(
         attestation = %ReplicationAttestation{version: 1},
         tx = %Transaction{address: address, type: type}
       ) do
    # Replication attestation version 1 does not contains storage confirmations,
    # so we ensure the transaction is valid looking at validation signature
    verify_attestation(attestation)

    validation_nodes_public_keys = get_validation_nodes_keys(tx)

    unless Transaction.valid_stamps_signature?(tx, validation_nodes_public_keys) do
      Logger.error("Transaction signature error in self repair",
        transaction_address: Base.encode16(address),
        transaction_type: type
      )

      raise "Transaction signature error in self repair"
    end
  end

  defp verify_transaction(
         attestation = %ReplicationAttestation{
           transaction_summary: %TransactionSummary{
             genesis_address: genesis_address,
             version: version
           }
         },
         tx
       )
       when version <= 2 do
    # Convert back the initial transaction_summary's movements (before AEIP-21) for validation
    tx_summary = TransactionSummary.from_transaction(tx, genesis_address, version)
    verify_attestation(%{attestation | transaction_summary: tx_summary})
  end

  defp verify_transaction(attestation, _tx), do: verify_attestation(attestation)

  # For the first node transaction of the network, there is not yet any public key stored in
  # DB. So for this transaction we take the public key of the first enrolled node
  defp get_validation_nodes_keys(
         tx = %Transaction{type: :node, previous_public_key: previous_tx_public_key}
       ) do
    %Node{first_public_key: first_node_public_key} = P2P.get_first_enrolled_node()

    if first_node_public_key == previous_tx_public_key do
      [[first_node_public_key]]
    else
      do_get_validation_nodes_keys(tx)
    end
  end

  defp get_validation_nodes_keys(tx), do: do_get_validation_nodes_keys(tx)

  defp do_get_validation_nodes_keys(%Transaction{
         validation_stamp: %ValidationStamp{timestamp: timestamp}
       }) do
    P2P.authorized_and_available_nodes(timestamp)
    |> Enum.map(fn %Node{first_public_key: first_public_key} ->
      TransactionChain.list_chain_public_keys(first_public_key, timestamp)
      |> Enum.reverse()
      |> Enum.map(&elem(&1, 0))
    end)
  end

  defp verify_attestation(attestation) do
    cond do
      not ReplicationAttestation.reached_threshold?(attestation) ->
        Logger.error("Threshold error in self repair on attestation #{inspect(attestation)}")

        raise "Attestation error in self repair"

      :ok != ReplicationAttestation.validate(attestation) ->
        Logger.error("Confirmation error in self repair on attestation #{inspect(attestation)}")

        raise "Attestation error in self repair"

      true ->
        :ok
    end
  end
end
