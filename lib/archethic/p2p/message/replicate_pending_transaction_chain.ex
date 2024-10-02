defmodule Archethic.P2P.Message.ReplicatePendingTransactionChain do
  @moduledoc false

  defstruct [:address, :genesis_address, :proof_of_validation]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Replication

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.AcknowledgeStorage

  @type t() :: %__MODULE__{
          address: Crypto.prepended_hash(),
          genesis_address: Crypto.prepended_hash(),
          proof_of_validation: ProofOfValidation.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{
          address: address,
          genesis_address: genesis_address,
          proof_of_validation: proof
        },
        sender_public_key
      ) do
    with {:ok, tx, validation_inputs} <- Replication.get_transaction_in_commit_pool(address),
         true <- ProofOfValidation.valid?(proof, tx.validation_stamp) do
      Task.Supervisor.start_child(Archethic.task_supervisors(), fn ->
        replicate_transaction(tx, validation_inputs, genesis_address, sender_public_key)
      end)

      %Ok{}
    else
      _ -> %Error{reason: :invalid_transaction}
    end
  end

  defp replicate_transaction(
         %Transaction{
           address: tx_address,
           validation_stamp: %ValidationStamp{timestamp: validation_time}
         } = tx,
         validation_inputs,
         genesis_address,
         sender_public_key
       ) do
    authorized_nodes = P2P.authorized_and_available_nodes(validation_time)

    Replication.sync_transaction_chain(tx, genesis_address, authorized_nodes)

    TransactionChain.write_inputs(
      tx_address,
      convert_unspent_outputs_to_inputs(validation_inputs)
    )

    P2P.send_message(sender_public_key, get_ack_storage(tx, genesis_address))
  end

  defp convert_unspent_outputs_to_inputs(validation_inputs) do
    Enum.map(validation_inputs, fn %VersionedUnspentOutput{
                                     unspent_output: utxo,
                                     protocol_version: protocol_version
                                   } ->
      %VersionedTransactionInput{
        input: TransactionInput.from_utxo(utxo),
        protocol_version: protocol_version
      }
    end)
  end

  defp get_ack_storage(tx = %Transaction{address: address}, genesis_address) do
    signature =
      tx
      |> TransactionSummary.from_transaction(genesis_address)
      |> TransactionSummary.serialize()
      |> Crypto.sign_with_first_node_key()

    %AcknowledgeStorage{
      address: address,
      signature: signature
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        address: address,
        genesis_address: genesis_address,
        proof_of_validation: proof
      }) do
    <<address::binary, genesis_address::binary, ProofOfValidation.serialize(proof)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {genesis_address, rest} = Utils.deserialize_address(rest)
    {proof, rest} = ProofOfValidation.deserialize(rest)

    {
      %__MODULE__{
        address: address,
        genesis_address: genesis_address,
        proof_of_validation: proof
      },
      rest
    }
  end
end
