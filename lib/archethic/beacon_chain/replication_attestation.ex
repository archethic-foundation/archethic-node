defmodule Archethic.BeaconChain.ReplicationAttestation do
  @moduledoc """
  Represents an attestation of a transaction replicated with a list of storage nodes confirmations
  """

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.PubSub

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error

  require Logger

  defstruct [:transaction_summary, confirmations: [], version: 1]

  @type t :: %__MODULE__{
          transaction_summary: TransactionSummary.t(),
          confirmations: list({position :: non_neg_integer(), signature :: binary()})
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(
        attestation = %__MODULE__{
          transaction_summary: %TransactionSummary{address: tx_address, type: tx_type}
        },
        _
      ) do
    case validate(attestation) do
      :ok ->
        PubSub.notify_replication_attestation(attestation)
        %Ok{}

      {:error, :invalid_confirmations_signatures} ->
        Logger.error("Invalid attestation signatures",
          transaction_address: Base.encode16(tx_address),
          transaction_type: tx_type
        )

        %Error{reason: :invalid_attestation}
    end
  end

  @doc """
  Serialize a replication attestation

  ## Examples

        iex> %ReplicationAttestation{
        ...>    version: 1,
        ...>    transaction_summary: %TransactionSummary{
        ...>      address: <<0, 0, 232, 183, 247, 15, 195, 209, 138, 58, 226, 218, 221, 135, 181, 43, 216, 164, 4, 187, 38,
        ...>        200, 170, 241, 23, 249, 75, 17, 23, 241, 185, 36, 15, 66>>,
        ...>      type: :transfer,
        ...>      timestamp: ~U[2022-01-27 09:14:22Z],
        ...>      fee: 10_000_000
        ...>    },
        ...>    confirmations: [
        ...>      {
        ...>        0,
        ...>        <<129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
        ...>         100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
        ...>         201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
        ...>         119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195>>
        ...>       }
        ...>    ]
        ...> } |> ReplicationAttestation.serialize()
        <<
          # Version
          1,
          # Tx address
          0, 0, 232, 183, 247, 15, 195, 209, 138, 58, 226, 218, 221, 135, 181, 43, 216,
          164, 4, 187, 38, 200, 170, 241, 23, 249, 75, 17, 23, 241, 185, 36, 15, 66,
          # Timestamp
          0, 0, 1, 126, 154, 208, 125, 176,
          # Transaction type
          253,
          # Fee
          0, 0, 0, 0, 0, 152, 150, 128,
          # Nb movements
          1, 0,
          # Nb confirmations
          1,
          # Replication node position
          0,
          # Signature size
          64,
          # Replication node signature
          129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
          100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
          201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
          119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195
        >>
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{
        version: 1,
        transaction_summary: transaction_summary,
        confirmations: confirmations
      }) do
    <<1::8, TransactionSummary.serialize(transaction_summary)::binary, length(confirmations)::8,
      serialize_confirmations(confirmations)::binary>>
  end

  defp serialize_confirmations(confirmations) do
    Enum.map(confirmations, fn {position, signature} ->
      <<position::8, byte_size(signature)::8, signature::binary>>
    end)
    |> :erlang.list_to_binary()
  end

  @doc """
  Deserialize a replication attestation

  ## Examples

      iex> <<1, 0, 0, 232, 183, 247, 15, 195, 209, 138, 58, 226, 218, 221, 135, 181, 43, 216,
      ...> 164, 4, 187, 38, 200, 170, 241, 23, 249, 75, 17, 23, 241, 185, 36, 15, 66,
      ...> 0, 0, 1, 126, 154, 208, 125, 176,
      ...> 253, 0, 0, 0, 0, 0, 152, 150, 128, 1, 0,
      ...> 1, 0,64,
      ...> 129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
      ...> 100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
      ...> 201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
      ...> 119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195>>
      ...> |> ReplicationAttestation.deserialize()
      {
        %ReplicationAttestation{
           version: 1,
           transaction_summary: %TransactionSummary{
             address: <<0, 0, 232, 183, 247, 15, 195, 209, 138, 58, 226, 218, 221, 135, 181, 43, 216, 164, 4, 187, 38,
               200, 170, 241, 23, 249, 75, 17, 23, 241, 185, 36, 15, 66>>,
             type: :transfer,
             timestamp: ~U[2022-01-27 09:14:22.000Z],
             fee: 10_000_000
           },
           confirmations: [
             {
               0,
               <<129, 204, 107, 81, 235, 88, 234, 207, 125, 1, 208, 227, 239, 175, 78, 217,
                100, 172, 67, 228, 131, 42, 177, 200, 54, 225, 34, 241, 35, 226, 108, 138,
                201, 2, 32, 75, 92, 49, 194, 42, 113, 154, 20, 43, 216, 176, 11, 159, 188,
                119, 6, 8, 48, 201, 244, 138, 99, 52, 22, 1, 97, 123, 140, 195>>
              }
           ]
        }, ""
      }

  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<1::8, rest::bitstring>>) do
    {tx_summary, <<nb_confirmations::8, rest::bitstring>>} = TransactionSummary.deserialize(rest)

    {confirmations, rest} = deserialize_confirmations(rest, nb_confirmations, [])

    {%__MODULE__{
       version: 1,
       transaction_summary: tx_summary,
       confirmations: confirmations
     }, rest}
  end

  defp deserialize_confirmations(rest, nb_replicas_signature, acc)
       when length(acc) == nb_replicas_signature do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_confirmations(rest, 0, _acc), do: {[], rest}

  defp deserialize_confirmations(
         <<position::8, sig_size::8, signature::binary-size(sig_size), rest::bitstring>>,
         nb_replicas_signature,
         acc
       ) do
    deserialize_confirmations(rest, nb_replicas_signature, [{position, signature} | acc])
  end

  @doc """
  Determine if the attestation is cryptographically valid
  """
  @spec validate(attestation :: t(), check_tx_summary_consistency? :: boolean()) ::
          :ok
          | {:error, :invalid_confirmations_signatures}
  def validate(
        %__MODULE__{
          transaction_summary:
            tx_summary = %TransactionSummary{
              address: tx_address,
              type: tx_type,
              timestamp: timestamp
            },
          confirmations: confirmations
        },
        check_summary_consistency? \\ false
      ) do
    tx_summary_payload = TransactionSummary.serialize(tx_summary)

    authorized_nodes = P2P.authorized_and_available_nodes(timestamp)

    storage_nodes = Election.chain_storage_nodes_with_type(tx_address, tx_type, authorized_nodes)

    with true <- check_summary_consistency?,
         :ok <- check_transaction_summary(storage_nodes, tx_summary) do
      validate_confirmations(confirmations, tx_summary_payload, storage_nodes)
    else
      false ->
        validate_confirmations(confirmations, tx_summary_payload, storage_nodes)

      {:error, _} = e ->
        e
    end
  end

  defp validate_confirmations([], _, _), do: {:error, :invalid_confirmations_signatures}

  defp validate_confirmations(confirmations, tx_summary_payload, storage_nodes) do
    valid_confirmations? =
      Enum.all?(confirmations, fn {node_index, signature} ->
        %Node{first_public_key: node_public_key} = Enum.at(storage_nodes, node_index)
        Crypto.verify?(signature, tx_summary_payload, node_public_key)
      end)

    if valid_confirmations? do
      :ok
    else
      {:error, :invalid_confirmations_signatures}
    end
  end

  defp check_transaction_summary(nodes, expected_summary, timeout \\ 500)

  defp check_transaction_summary([], _, _), do: {:error, :network_issue}

  defp check_transaction_summary(
         nodes,
         expected_summary = %TransactionSummary{
           address: address,
           type: type
         },
         _timeout
       ) do
    conflict_resolver = fn results ->
      case Enum.find(results, &match?(%TransactionSummary{address: ^address, type: ^type}, &1)) do
        nil ->
          %NotFound{}

        tx_summary ->
          tx_summary
      end
    end

    case P2P.quorum_read(
           nodes,
           %GetTransactionSummary{address: address},
           conflict_resolver
         ) do
      {:ok, ^expected_summary} ->
        :ok

      {:ok, recv = %TransactionSummary{}} ->
        Logger.warning(
          "Transaction summary received is different #{inspect(recv)} - expect #{inspect(expected_summary)}",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

      {:ok, %NotFound{}} ->
        Logger.warning("Transaction summary was not found",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        {:error, :invalid_summary}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end
end
