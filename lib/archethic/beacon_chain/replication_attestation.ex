defmodule Archethic.BeaconChain.ReplicationAttestation do
  @moduledoc """
  Represents an attestation of a transaction replicated with a list of storage nodes confirmations
  """

  alias Archethic.Crypto

  alias Archethic.Election.HypergeometricDistribution

  alias Archethic.P2P

  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  defstruct [:transaction_summary, confirmations: [], version: 1]

  @type t :: %__MODULE__{
          transaction_summary: TransactionSummary.t(),
          confirmations: list({position :: non_neg_integer(), signature :: binary()})
        }

  # Minimum 10 nodes to start verifying the threshold
  @minimum_nodes_for_threshold 10
  # Minimum 35% of the expected confirmations must be present
  @confirmations_threshold 0.35

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
        ...>      fee: 10_000_000,
        ...>      validation_stamp_checksum: <<17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
        ...>        167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219>>
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
          # Transaction summary version
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
          # Validation stamp checksum
          17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
          167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219,
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

      iex> <<1, 1, 0, 0, 232, 183, 247, 15, 195, 209, 138, 58, 226, 218, 221, 135, 181, 43, 216,
      ...> 164, 4, 187, 38, 200, 170, 241, 23, 249, 75, 17, 23, 241, 185, 36, 15, 66,
      ...> 0, 0, 1, 126, 154, 208, 125, 176,
      ...> 253, 0, 0, 0, 0, 0, 152, 150, 128, 1, 0,
      ...> 17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
      ...> 167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219,
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
             fee: 10_000_000,
             validation_stamp_checksum: <<17, 8, 18, 246, 127, 161, 225, 240, 17, 127, 111, 61, 112, 36, 28, 26, 66,
               167, 176, 119, 17, 169, 60, 36, 119, 204, 81, 109, 144, 66, 249, 219>>
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
  Return the index of the node based on the authorized node at this timestamp
  """
  @spec get_node_index(Crypto.key(), DateTime.t()) :: non_neg_integer()
  def get_node_index(node_public_key, timestamp) do
    P2P.authorized_and_available_nodes(timestamp)
    |> Enum.sort_by(& &1.first_public_key)
    |> Enum.find_index(&(&1.first_public_key == node_public_key))
  end

  @doc """
  Determine if the attestation is cryptographically valid
  """
  @spec validate(attestation :: t()) ::
          :ok
          | {:error, :invalid_confirmations_signatures}
  def validate(%__MODULE__{
        transaction_summary: tx_summary = %TransactionSummary{timestamp: timestamp},
        confirmations: confirmations
      }) do
    tx_summary_payload = TransactionSummary.serialize(tx_summary)

    node_public_keys =
      P2P.authorized_and_available_nodes(timestamp)
      |> Enum.map(& &1.first_public_key)
      |> Enum.sort()

    validate_confirmations(confirmations, tx_summary_payload, node_public_keys)
  end

  defp validate_confirmations([], _, _), do: {:error, :invalid_confirmations_signatures}

  defp validate_confirmations(confirmations, tx_summary_payload, node_public_keys) do
    valid_confirmations? =
      Enum.all?(confirmations, fn {node_index, signature} ->
        public_key = Enum.at(node_public_keys, node_index)
        Crypto.verify?(signature, tx_summary_payload, public_key)
      end)

    if valid_confirmations? do
      :ok
    else
      {:error, :invalid_confirmations_signatures}
    end
  end

  @doc """
  Take a list of attestations and reduce them to return a list of unique attestation
  for a transaction with all the confirmations
  """
  @spec reduce_confirmations(Enumerable.t(t())) :: Enumerable.t(t())
  def reduce_confirmations(attestations) do
    attestations
    |> Stream.transform(
      # start function, init acc
      fn -> %{} end,
      # reducer function, return empty enum, accumulate replication attestation by address in acc
      fn attestation = %__MODULE__{
           transaction_summary: %TransactionSummary{address: address},
           confirmations: confirmations
         },
         acc ->
        # Accumulate distinct confirmations in a replication attestation
        acc =
          Map.update(acc, address, attestation, fn reduced_attest ->
            Map.update!(reduced_attest, :confirmations, &((&1 ++ confirmations) |> Enum.uniq()))
          end)

        {[], acc}
      end,
      # last function, return acc in the enumeration
      fn acc -> {Map.values(acc), acc} end,
      # after function, do nothing
      fn _ -> :ok end
    )
  end

  @doc """
  Return true if the attestation reached the minimum confirmations threshold
  """
  @spec reached_threshold?(t()) :: boolean()
  def reached_threshold?(%__MODULE__{
        transaction_summary: %TransactionSummary{timestamp: timestamp},
        confirmations: confirmations
      }) do
    # For security reason we reject the attestation with less than 35% of expected confirmations
    with nb_nodes when nb_nodes > 0 <- P2P.authorized_and_available_nodes(timestamp) |> length(),
         replicas_count <- HypergeometricDistribution.run_simulation(nb_nodes),
         true <- replicas_count > @minimum_nodes_for_threshold do
      length(confirmations) >= replicas_count * @confirmations_threshold
    else
      _ -> true
    end
  end
end
