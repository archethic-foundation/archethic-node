defmodule Archethic.BeaconChain.ReplicationAttestation do
  @moduledoc """
  Represents an attestation of a transaction replicated with a list of storage nodes confirmations
  """

  alias Archethic.Crypto

  alias Archethic.Election.StorageConstraints

  alias Archethic.P2P

  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  defstruct [:transaction_summary, confirmations: [], version: 2]

  @type t :: %__MODULE__{
          transaction_summary: TransactionSummary.t(),
          confirmations: list({position :: non_neg_integer(), signature :: binary()})
        }

  @limit_v1_timestamp ~U[2023-06-30 00:00:00.000Z]

  # Minimum 10 nodes to start verifying the threshold
  @minimum_nodes_for_threshold 10
  # Minimum 35% of the expected confirmations must be present
  @confirmations_threshold 0.35

  @doc """
  Serialize a replication attestation
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{version: 1, transaction_summary: transaction_summary}) do
    <<1::8, TransactionSummary.serialize(transaction_summary)::binary>>
  end

  def serialize(%__MODULE__{
        version: version,
        transaction_summary: transaction_summary,
        confirmations: confirmations
      }) do
    <<version::8, TransactionSummary.serialize(transaction_summary)::binary,
      length(confirmations)::8, serialize_confirmations(confirmations)::binary>>
  end

  defp serialize_confirmations(confirmations) do
    Enum.map(confirmations, fn {position, signature} ->
      <<position::8, byte_size(signature)::8, signature::binary>>
    end)
    |> :erlang.list_to_binary()
  end

  @doc """
  Deserialize a replication attestation
  """
  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<1::8, rest::bitstring>>) do
    {tx_summary, <<rest::bitstring>>} = TransactionSummary.deserialize(rest)

    {%__MODULE__{version: 1, transaction_summary: tx_summary}, rest}
  end

  def deserialize(<<version::8, rest::bitstring>>) do
    {tx_summary, <<nb_confirmations::8, rest::bitstring>>} = TransactionSummary.deserialize(rest)

    {confirmations, rest} = deserialize_confirmations(rest, nb_confirmations, [])

    {%__MODULE__{
       version: version,
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
        version: 1,
        transaction_summary: %TransactionSummary{timestamp: timestamp}
      }) do
    # Attestation V1 are legacy and usable only before a specific date.
    if DateTime.compare(timestamp, @limit_v1_timestamp) == :lt,
      do: :ok,
      else: {:error, :invalid_confirmations_signatures}
  end

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
  # No verification for attestation V1 as they don't have confirmations
  def reached_threshold?(%__MODULE__{version: 1}), do: true

  def reached_threshold?(%__MODULE__{
        transaction_summary: %TransactionSummary{timestamp: timestamp},
        confirmations: confirmations
      }) do
    # For security reason we reject the attestation with less than 35% of expected confirmations
    %StorageConstraints{number_replicas: number_replicas_fun} = StorageConstraints.new()

    with nb_nodes when nb_nodes > 0 <- P2P.authorized_and_available_nodes(timestamp) |> length(),
         replicas_count <- number_replicas_fun.(nb_nodes),
         true <- replicas_count > @minimum_nodes_for_threshold do
      length(confirmations) >= replicas_count * @confirmations_threshold
    else
      _ -> true
    end
  end
end
