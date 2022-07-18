defmodule Archethic.BeaconChain.ReplicationAttestation do
  @moduledoc """
  Represents an attestation of a transaction replicated with a list of storage nodes confirmations
  """

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils.VarInt

  defstruct [:transaction_summary, confirmations: [], version: 1]

  @type t :: %__MODULE__{
          transaction_summary: TransactionSummary.t(),
          confirmations: list({position :: non_neg_integer(), signature :: binary()})
        }

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
          1, 1,
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
    encoded_confirmation_length = length(confirmations) |> VarInt.from_value()

    <<1::8, TransactionSummary.serialize(transaction_summary)::binary,
      encoded_confirmation_length::binary, serialize_confirmations(confirmations)::binary>>
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
      ...> 1, 1, 0,64,
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
    {tx_summary, <<rest::bitstring>>} = TransactionSummary.deserialize(rest)

    {nb_confirmations, rest} = rest |> VarInt.get_value()
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
  @spec validate(t()) ::
          :ok
          | {:error, :invalid_confirmations_signatures}
  def validate(%__MODULE__{
        transaction_summary:
          tx_summary = %TransactionSummary{
            address: tx_address,
            type: tx_type,
            timestamp: timestamp
          },
        confirmations: confirmations
      }) do
    tx_summary_payload = TransactionSummary.serialize(tx_summary)

    authorized_nodes =
      case P2P.authorized_nodes(timestamp) do
        # Should only happens when the network bootstrap
        [] ->
          P2P.authorized_nodes()

        nodes ->
          nodes
      end

    storage_nodes = Election.chain_storage_nodes_with_type(tx_address, tx_type, authorized_nodes)

    if valid_confirmations?(confirmations, tx_summary_payload, storage_nodes) do
      :ok
    else
      {:error, :invalid_confirmations_signatures}
    end
  end

  defp valid_confirmations?([], _, _), do: false

  defp valid_confirmations?(confirmations, tx_summary_payload, storage_nodes) do
    confirmations
    |> Enum.all?(fn {node_index, signature} ->
      %Node{first_public_key: node_public_key} = Enum.at(storage_nodes, node_index)
      Crypto.verify?(signature, tx_summary_payload, node_public_key)
    end)
  end
end
