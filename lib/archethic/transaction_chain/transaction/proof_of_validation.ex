defmodule Archethic.TransactionChain.Transaction.ProofOfValidation do
  @moduledoc """
  Handle the Proof Of Validation signatures containing
  - The aggregated signatures
  - Nodes bitmask (bitmask of nodes used for the signatures)

  Proof of Validation aggregate all valid Cross Validation Stamp signatures
  It require a threshold of cross stamp without error based on the expected number
  of validations nodes
  """

  alias Archethic.Crypto

  alias Archethic.Election
  alias Archethic.Election.StorageConstraints

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils

  @enforce_keys [:signature, :nodes_bitmask]
  defstruct [:signature, :nodes_bitmask, version: 1]

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          signature: binary(),
          nodes_bitmask: bitstring()
        }

  # Minimum 75% of the expected cross validation must be present
  @validation_threshold 0.75

  @doc """
  Determines if enough cross validation stamps have been received to create the aggregated signature
  Returns
    - :reached if enough stamps are valid
    - :not_reached if not enough stamps received yet
    - :error if it's not possible to reach the threshold
  """
  @spec get_state(stamps :: list(), validation_time :: DateTime.t()) ::
          :reached | :not_reached | :error
  def get_state(stamps, validation_time) do
    valid_cross = filter_valid_cross_stamps(stamps)

    nb_max = get_nb_validation_nodes(validation_time)
    nb_valid = Enum.count(valid_cross)

    if nb_valid / nb_max >= @validation_threshold do
      :reached
    else
      remaining = nb_max - Enum.count(stamps)

      # If the remaining stamp to receive cannot reach the threshold we return an error
      if (nb_valid + remaining) / nb_max >= @validation_threshold,
        do: :not_reached,
        else: :error
    end
  end

  @doc """
  Construct the proof of validation aggregating valid cross stamps
  """
  @spec create(
          stamps :: list({Crypto.key(), CrossValidationStamp.t()}),
          validation_time :: DateTime.t()
        ) :: t()
  def create(stamps, validation_time) do
    valid_cross = filter_valid_cross_stamps(stamps)

    {public_keys, signatures} =
      Enum.reduce(
        valid_cross,
        {[], []},
        fn {_from, %CrossValidationStamp{node_public_key: public_key, signature: signature}},
           {public_keys, signatures} ->
          {[public_key | public_keys], [signature | signatures]}
        end
      )

    aggregated_signature = Crypto.aggregate_signatures(signatures, public_keys)

    authorized_nodes = get_sorted_authorized_nodes(validation_time)

    bitmask =
      Enum.reduce(valid_cross, <<>>, fn {from, _}, acc ->
        index = Enum.find_index(authorized_nodes, &(&1.first_public_key == from))
        Utils.set_bitstring_bit(acc, index)
      end)

    %__MODULE__{signature: aggregated_signature, nodes_bitmask: bitmask}
  end

  @doc """
  Returns the list of node that signed the proof of validation
  """
  @spec get_nodes(proof :: t(), validation_time :: DateTime.t()) :: list(Node.t())
  def get_nodes(%__MODULE__{nodes_bitmask: bitmask}, validation_time) do
    nodes = get_sorted_authorized_nodes(validation_time)

    bitmask
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.filter(&(elem(&1, 0) == 1))
    |> Enum.map(fn {_, index} -> Enum.at(nodes, index) end)
  end

  @doc """
  Validate a proof of validation
  - Number of validation reach the threshold
  - aggregated signature is valid
  """
  @spec valid?(proof :: t(), validation_stamp :: ValidationStamp.t()) :: boolean()
  def valid?(
        proof = %__MODULE__{signature: signature},
        validation_stamp = %ValidationStamp{timestamp: validation_time}
      ) do
    nb_max_validation_nodes = get_nb_validation_nodes(validation_time)
    validation_nodes = get_nodes(proof, validation_time)

    if Enum.count(validation_nodes) / nb_max_validation_nodes >= @validation_threshold do
      aggregated_public_key =
        validation_nodes
        |> Enum.map(& &1.mining_public_key)
        |> Crypto.aggregate_mining_public_keys()

      raw_data = CrossValidationStamp.get_row_data_to_sign(validation_stamp, [])

      Crypto.verify?(signature, raw_data, aggregated_public_key)
    else
      false
    end
  end

  defp filter_valid_cross_stamps(stamps) do
    {valid_cross, _invalid_cross} =
      Enum.split_with(stamps, fn {_from, %CrossValidationStamp{inconsistencies: inconsistencies}} ->
        Enum.empty?(inconsistencies)
      end)

    valid_cross
  end

  defp get_sorted_authorized_nodes(validation_time) do
    validation_time |> P2P.authorized_and_available_nodes() |> Enum.sort_by(& &1.first_public_key)
  end

  defp get_nb_validation_nodes(validation_time) do
    %StorageConstraints{number_replicas: nb_replicas_fn} = Election.get_storage_constraints()
    validation_time |> P2P.authorized_and_available_nodes() |> nb_replicas_fn.()
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{version: version, signature: signature, nodes_bitmask: bitmask}) do
    <<version::16, byte_size(signature)::8, signature::binary, bit_size(bitmask)::8,
      bitmask::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) do
    <<version::16, signature_size::8, signature::binary-size(signature_size), bitmask_size::8,
      bitmask::bitstring-size(bitmask_size), rest::bitstring>> = bin

    {%__MODULE__{version: version, signature: signature, nodes_bitmask: bitmask}, rest}
  end
end
