defmodule Archethic.SelfRepair.Sync.TransactionHandler do
  @moduledoc false

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.P2P.Message

  alias Archethic.Replication

  alias Archethic.SelfRepair

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
  def download_transaction?(
        %ReplicationAttestation{
          transaction_summary: %TransactionSummary{
            address: address,
            version: 1
          }
        },
        _
      ),
      do: not TransactionChain.transaction_exists?(address, :io)

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
    node_key = Crypto.first_node_public_key()

    if Election.chain_storage_node?(address, type, node_key, node_list) or
         Election.chain_storage_node?(genesis_address, node_key, node_list) do
      not TransactionChain.transaction_exists?(address)
    else
      io_node?(movements_addresses, node_key, node_list) and
        not TransactionChain.transaction_exists?(address, :io)
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
        raise SelfRepair.Error,
          function: "download_transaction",
          message: "Cannot fetch the transaction to sync because of #{inspect(reason)}",
          address: address
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

    resolved_addresses = get_resolved_addresses(attestation)

    node_list = [P2P.get_node_info() | node_list] |> P2P.distinct_nodes()
    node_public_key = Crypto.first_node_public_key()

    cond do
      Election.chain_storage_node?(address, type, node_public_key, node_list) ->
        Replication.sync_transaction_chain(tx, genesis_address, node_list,
          self_repair?: true,
          resolved_addresses: resolved_addresses
        )

      Election.chain_storage_node?(genesis_address, node_public_key, node_list) ->
        Replication.sync_transaction_chain(tx, genesis_address, node_list,
          self_repair?: true,
          resolved_addresses: resolved_addresses
        )

      io_node?(movements_addresses, node_public_key, node_list) ->
        Replication.synchronize_io_transaction(tx, genesis_address,
          self_repair?: true,
          resolved_addresses: resolved_addresses,
          download_nodes: node_list
        )

      true ->
        :ok
    end
  end

  defp get_resolved_addresses(%ReplicationAttestation{
         transaction_summary: %TransactionSummary{
           version: version,
           movements_addresses: addresses
         }
       })
       when version <= 2 do
    # When retrieving transaction summary, Sync module resolved addresses
    # for transaction summary before AEIP-21, addresses are concatenated in movements addresses
    # with as genesis address is inserted after the last address
    addresses
    |> Enum.chunk_every(2)
    |> Enum.map(&List.to_tuple/1)
    |> Map.new()
  end

  defp get_resolved_addresses(_), do: %{}

  defp io_node?(addresses, node_public_key, nodes),
    do: addresses |> Election.io_storage_nodes(nodes) |> Utils.key_in_node_list?(node_public_key)

  defp verify_transaction(
         attestation = %ReplicationAttestation{version: 1},
         tx = %Transaction{address: address}
       ) do
    # Replication attestation version 1 does not contains storage confirmations,
    # so we ensure the transaction is valid looking at validation signature
    verify_attestation(attestation)

    validation_nodes_public_keys = get_validation_nodes_keys(tx)

    unless Transaction.valid_stamps_signature?(tx, validation_nodes_public_keys) do
      raise SelfRepair.Error,
        function: "verify_transaction",
        message: "Transaction signature error in self repair",
        address: address
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

        raise SelfRepair.Error,
          function: "verify_attestation",
          message: "Threshold error in self repair on attestation #{inspect(attestation)}"

      :ok != ReplicationAttestation.validate(attestation) ->
        raise SelfRepair.Error,
          function: "verify_attestation",
          message: "Confirmation error in self repair on attestation #{inspect(attestation)}"

      true ->
        :ok
    end
  end
end
