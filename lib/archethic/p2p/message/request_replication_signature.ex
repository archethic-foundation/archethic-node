defmodule Archethic.P2P.Message.RequestReplicationSignature do
  @moduledoc false

  defstruct [:address, :proof_of_validation]

  use Retry

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.ReplicationSignatureDone
  alias Archethic.Replication
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfReplication.Signature
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils

  @type t() :: %__MODULE__{
          address: Crypto.prepended_hash(),
          proof_of_validation: ProofOfValidation.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: address, proof_of_validation: proof_of_validation}, _) do
    Archethic.task_supervisors()
    |> Task.Supervisor.start_child(fn ->
      node_public_key = Crypto.first_node_public_key()

      with {:ok, tx} <- get_transaction(address),
           authorized_nodes <- P2P.authorized_and_available_nodes(tx.validation_stamp.timestamp),
           true <- Election.chain_storage_node?(address, node_public_key, authorized_nodes),
           true <- valid_proof_of_validation?(proof_of_validation, tx, authorized_nodes) do
        Replication.add_proof_of_validation_to_commit_pool(proof_of_validation, address)

        tx = %Transaction{tx | proof_of_validation: proof_of_validation}
        tx_summary = TransactionSummary.from_transaction(tx)

        message = %ReplicationSignatureDone{
          address: address,
          replication_signature: Signature.create(tx_summary)
        }

        tx
        |> get_validation_nodes(authorized_nodes)
        |> P2P.broadcast_message(message)
      else
        _ -> :skip
      end
    end)

    %Ok{}
  end

  defp get_transaction(address) do
    # As validation can happen without all node returned the validation response
    # it is possible to receive this message before processing the validation
    retry_while with: constant_backoff(100) |> expiry(2000) do
      case Replication.get_transaction_in_commit_pool(address) do
        {:ok, tx, _} -> {:halt, {:ok, tx}}
        er -> {:cont, er}
      end
    end
  end

  defp valid_proof_of_validation?(
         proof,
         %Transaction{address: address, validation_stamp: stamp},
         authorized_nodes
       ) do
    authorized_nodes
    |> ProofOfValidation.get_election(address)
    |> ProofOfValidation.valid?(proof, stamp)
  end

  defp get_validation_nodes(
         tx = %Transaction{
           address: address,
           validation_stamp: %ValidationStamp{proof_of_election: proof_of_election}
         },
         authorized_nodes
       ) do
    storage_nodes = Election.chain_storage_nodes(address, authorized_nodes)
    Election.validation_nodes(tx, proof_of_election, authorized_nodes, storage_nodes)
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, proof_of_validation: proof}) do
    <<address::binary, ProofOfValidation.serialize(proof)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {proof, rest} = ProofOfValidation.deserialize(rest)

    {%__MODULE__{address: address, proof_of_validation: proof}, rest}
  end
end
