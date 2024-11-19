defmodule Archethic.P2P.Message.ReplicatePendingTransactionChain do
  @moduledoc false

  defstruct [:address, :genesis_address, :proof_of_replication]

  use Retry

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.AcknowledgeStorage
  alias Archethic.Replication

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfReplication
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils

  @type t() :: %__MODULE__{
          address: Crypto.prepended_hash(),
          genesis_address: Crypto.prepended_hash(),
          proof_of_replication: ProofOfReplication.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          address: address,
          genesis_address: genesis_address,
          proof_of_replication: proof
        },
        sender_public_key
      ) do
    Task.Supervisor.start_child(Archethic.task_supervisors(), fn ->
      node_public_key = Crypto.first_node_public_key()

      with {:ok, tx, validation_inputs} <- get_transaction_data(address),
           authorized_nodes <- P2P.authorized_and_available_nodes(tx.validation_stamp.timestamp),
           true <- Election.chain_storage_node?(address, node_public_key, authorized_nodes),
           elected_nodes <- ProofOfReplication.get_election(authorized_nodes, address),
           tx_summary <- TransactionSummary.from_transaction(tx, genesis_address),
           true <- ProofOfReplication.valid?(elected_nodes, proof, tx_summary) do
        # tx = %Transaction{tx | proof_of_replication: proof}
        replicate_transaction(tx, validation_inputs, genesis_address, sender_public_key)
      else
        _ -> :skip
      end
    end)

    %Ok{}
  end

  defp get_transaction_data(address) do
    # As validation can happen without all node returned the validation response
    # it is possible to receive this message before processing the validation
    case get_data_in_tx_pool(address) do
      res = {:ok, _, _} -> res
      _ -> fetch_tx_data(address)
    end
  end

  defp get_data_in_tx_pool(address) do
    retry_while with: constant_backoff(100) |> expiry(2000) do
      case Replication.pop_transaction_in_commit_pool(address) do
        {:ok, tx, validation_utxo} ->
          validation_inputs = convert_unspent_outputs_to_inputs(validation_utxo)
          {:halt, {:ok, tx, validation_inputs}}

        er ->
          {:cont, er}
      end
    end
  end

  defp fetch_tx_data(address) do
    storage_nodes = Election.storage_nodes(address, P2P.authorized_and_available_nodes())

    res =
      [
        Task.async(fn ->
          TransactionChain.fetch_transaction(address, storage_nodes,
            search_mode: :remote,
            acceptance_resolver: :accept_transaction
          )
        end),
        Task.async(fn -> TransactionChain.fetch_inputs(address, storage_nodes) end)
      ]
      |> Task.await_many(P2P.Message.get_max_timeout() + 100)

    case res do
      [{:ok, tx}, validation_inputs] -> {:ok, tx, validation_inputs}
      _ -> {:error, :transaction_not_exists}
    end
  end

  defp replicate_transaction(
         tx = %Transaction{
           address: tx_address,
           validation_stamp: %ValidationStamp{timestamp: validation_time}
         },
         validation_inputs,
         genesis_address,
         sender_public_key
       ) do
    authorized_nodes = P2P.authorized_and_available_nodes(validation_time)

    Replication.sync_transaction_chain(tx, genesis_address, authorized_nodes)
    TransactionChain.write_inputs(tx_address, validation_inputs)

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
        proof_of_replication: proof
      }) do
    <<address::binary, genesis_address::binary, ProofOfReplication.serialize(proof)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {genesis_address, rest} = Utils.deserialize_address(rest)
    {proof, rest} = ProofOfReplication.deserialize(rest)

    {
      %__MODULE__{
        address: address,
        genesis_address: genesis_address,
        proof_of_replication: proof
      },
      rest
    }
  end
end
