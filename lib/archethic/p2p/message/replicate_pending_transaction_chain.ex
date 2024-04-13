defmodule Archethic.P2P.Message.ReplicatePendingTransactionChain do
  @moduledoc false

  defstruct [:address, :genesis_address]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Replication
  alias Archethic.TaskSupervisor
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.AcknowledgeStorage

  require OpenTelemetry.Tracer

  @type t() :: %__MODULE__{
          address: binary(),
          genesis_address: binary()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t() | Error.t()
  def process(
        %__MODULE__{address: address, genesis_address: genesis_address},
        %{
          sender_public_key: sender_public_key,
          trace: trace
        }
      ) do
    Utils.extract_progagated_context(trace)

    OpenTelemetry.Tracer.with_span "replicate transaction" do
      OpenTelemetry.Tracer.set_attribute(
        "node",
        P2P.get_node_info() |> Node.endpoint()
      )

      case Replication.get_transaction_in_commit_pool(address) do
        {:ok,
         tx = %Transaction{
           address: tx_address,
           validation_stamp: %ValidationStamp{timestamp: validation_time}
         }, validation_inputs} ->
          Task.Supervisor.start_child(TaskSupervisor, fn ->
            authorized_nodes = P2P.authorized_and_available_nodes(validation_time)

            Replication.sync_transaction_chain(tx, genesis_address, authorized_nodes)

            TransactionChain.write_inputs(
              tx_address,
              convert_unspent_outputs_to_inputs(validation_inputs)
            )

            P2P.send_message(sender_public_key, get_ack_storage(tx, genesis_address))
          end)

          %Ok{}

        {:error, :transaction_not_exists} ->
          %Error{reason: :invalid_transaction}
      end
    end
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
  def serialize(%__MODULE__{address: address, genesis_address: genesis_address}) do
    <<address::binary, genesis_address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {genesis_address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{
        address: address,
        genesis_address: genesis_address
      },
      rest
    }
  end
end
