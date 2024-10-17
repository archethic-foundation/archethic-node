defmodule Archethic.P2P.Message.ValidateTransaction do
  @moduledoc false

  @enforce_keys [:transaction, :inputs]
  defstruct [:transaction, :contract_context, :inputs]

  require Logger
  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.CrossValidationDone
  alias Archethic.P2P.Message.Ok
  alias Archethic.Replication
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          contract_context: nil | Contract.Context.t(),
          inputs: list(VersionedUnspentOutput.t())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{transaction: tx, contract_context: contract_context, inputs: inputs},
        from
      ) do
    %Transaction{
      address: tx_address,
      type: type,
      validation_stamp: %ValidationStamp{
        proof_of_election: proof_of_election,
        timestamp: timestamp
      }
    } = tx

    authorized_nodes = P2P.authorized_and_available_nodes(timestamp)
    storage_nodes = Election.chain_storage_nodes(tx_address, authorized_nodes)

    validation_nodes =
      Election.validation_nodes(tx, proof_of_election, authorized_nodes, storage_nodes)

    node_key = Crypto.first_node_public_key()

    meta = [transaction_address: tx_address, transaction_type: type]

    cond do
      not Utils.key_in_node_list?(validation_nodes, from) ->
        Logger.warning("Received validate tx message from non validation node", meta)

      not Utils.key_in_node_list?(storage_nodes, node_key) ->
        Logger.warning("Received validate tx message while node is not storage node", meta)

      true ->
        Task.Supervisor.start_child(Archethic.task_supervisors(), fn ->
          do_validate_transaction(tx, contract_context, inputs, validation_nodes)
        end)
    end

    %Ok{}
  end

  defp do_validate_transaction(tx, contract_context, inputs, validation_nodes) do
    %Transaction{address: tx_address, validation_stamp: %ValidationStamp{error: stamp_error}} = tx

    # Since the transaction can be validated before a node finish processing this message
    # we store the transaction directly in the waiting pool
    if stamp_error == nil, do: Replication.add_transaction_to_commit_pool(tx, inputs)

    message = %CrossValidationDone{
      address: tx_address,
      cross_validation_stamp: Replication.validate_transaction(tx, contract_context, inputs)
    }

    P2P.broadcast_message(validation_nodes, message)
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx, contract_context: nil, inputs: inputs}) do
    inputs_bin =
      inputs
      |> Enum.map(&VersionedUnspentOutput.serialize/1)
      |> :erlang.list_to_bitstring()

    inputs_size =
      inputs
      |> length()
      |> Utils.VarInt.from_value()

    <<Transaction.serialize(tx)::bitstring, 0::8, inputs_size::binary, inputs_bin::bitstring>>
  end

  def serialize(%__MODULE__{transaction: tx, contract_context: contract_context, inputs: inputs}) do
    inputs_bin =
      inputs
      |> Enum.map(&VersionedUnspentOutput.serialize/1)
      |> :erlang.list_to_bitstring()

    inputs_size =
      inputs
      |> length()
      |> Utils.VarInt.from_value()

    <<Transaction.serialize(tx)::bitstring, 1::8,
      Contract.Context.serialize(contract_context)::bitstring, inputs_size::binary,
      inputs_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) when is_bitstring(bin) do
    {tx = %Transaction{validation_stamp: %ValidationStamp{protocol_version: protocol_version}},
     rest} = Transaction.deserialize(bin)

    {contract_context, rest} =
      case rest do
        <<0::8, rest::bitstring>> -> {nil, rest}
        <<1::8, rest::bitstring>> -> Contract.Context.deserialize(rest)
      end

    {inputs_size, rest} = Utils.VarInt.get_value(rest)
    {inputs, rest} = deserialize_versioned_unspent_output_list(rest, inputs_size, [])

    {
      %__MODULE__{transaction: tx, contract_context: contract_context, inputs: inputs},
      rest
    }
  end

  defp deserialize_versioned_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_unspent_output_list(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end
end
