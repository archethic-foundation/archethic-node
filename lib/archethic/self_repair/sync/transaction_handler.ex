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
            type: type,
            movements_addresses: mvt_addresses
          }
        },
        node_list
      ) do
    chain_storage_nodes = Election.chain_storage_nodes_with_type(address, type, node_list)

    if Utils.key_in_node_list?(chain_storage_nodes, Crypto.first_node_public_key()) do
      not TransactionChain.transaction_exists?(address)
    else
      io_node? =
        Enum.any?(mvt_addresses, fn address ->
          address
          |> Election.chain_storage_nodes(node_list)
          |> Utils.key_in_node_list?(Crypto.first_node_public_key())
        end)

      io_node? and not TransactionChain.transaction_exists?(address, :io)
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
            expected_summary = %TransactionSummary{address: address, type: type}
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

    acceptance_resolver = fn
      {:ok, %Transaction{address: ^address}} -> true
      _ -> false
    end

    case TransactionChain.fetch_transaction_remotely(
           address,
           storage_nodes,
           timeout,
           acceptance_resolver
         ) do
      {:ok, tx = %Transaction{}} ->
        summary = TransactionSummary.from_transaction(tx)

        # Control if the downloaded transaction is the expected one
        if summary != expected_summary do
          Logger.error(
            "Dowloaded transaction is different than expected one. Expected #{inspect(expected_summary)}, got summary #{inspect(summary)}",
            transaction_address: Base.encode16(address),
            transaction_type: type
          )

          raise "Transaction downloaded is different than expected"
        end

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
        attestation,
        tx = %Transaction{
          address: address,
          type: type
        },
        node_list
      ) do
    :ok = verify_attestation(attestation)

    node_list = [P2P.get_node_info() | node_list] |> P2P.distinct_nodes()

    cond do
      Election.chain_storage_node?(address, type, Crypto.first_node_public_key(), node_list) ->
        Replication.sync_transaction_chain(tx, node_list, true)

      Election.io_storage_node?(tx, Crypto.first_node_public_key(), node_list) ->
        Replication.synchronize_io_transaction(tx, true)

      true ->
        :ok
    end
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
