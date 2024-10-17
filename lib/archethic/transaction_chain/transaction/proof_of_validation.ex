defmodule Archethic.TransactionChain.Transaction.ProofOfValidation do
  @moduledoc """
  Handle the Proof Of Validation signatures containing
  - The aggregated signatures
  - Nodes bitmask (bitmask of nodes used for the signatures)

  Proof of Validation aggregate all valid Cross Validation Stamp signatures
  It require a number of cross stamp without error equal or superior to the number 
  returned by the hypergeometric distribution to be valid
  """

  alias Archethic.Crypto

  alias Archethic.Election
  alias Archethic.Election.StorageConstraints

  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.Utils

  alias __MODULE__.ElectedNodes

  @enforce_keys [:signature, :nodes_bitmask]
  defstruct [:signature, :nodes_bitmask, version: 1]

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          signature: binary(),
          nodes_bitmask: bitstring()
        }

  @bls_signature_size 96

  defmodule ElectedNodes do
    @moduledoc """
    Struct holding sorted validation nodes elected for the transaction
    and the required number of validations
    """
    alias Archethic.P2P.Node

    @enforce_keys [:required_validations, :validation_nodes]
    defstruct [:required_validations, validation_nodes: []]

    @type t :: %__MODULE__{
            required_validations: non_neg_integer(),
            validation_nodes: list(Node.t())
          }
  end

  @doc """
  Returns the sorted list of nodes and the required number of validation nodes
  The input nodes list needs to be the authorized and available nodes at the time of the transaction
  """
  @spec get_election(nodes :: list(Node.t()), tx_address :: Crypto.prepended_hash()) ::
          ElectedNodes.t()
  def get_election(nodes, tx_address) do
    required_validations = get_nb_required_validations(nodes)
    validation_nodes = Election.storage_nodes(tx_address, nodes)

    %ElectedNodes{
      required_validations: required_validations,
      validation_nodes: Enum.sort_by(validation_nodes, & &1.first_public_key)
    }
  end

  @doc """
  Determines if enough cross validation stamps have been received to create the aggregated signature
  Returns
    - :reached if enough stamps are valid
    - :not_reached if not enough stamps received yet
    - :error if it's not possible to reach the required validations
  """
  @spec get_state(nodes :: ElectedNodes.t(), stamps :: list()) ::
          :reached | :not_reached | :error
  def get_state(
        %ElectedNodes{required_validations: required_validations, validation_nodes: nodes},
        stamps
      ) do
    nb_valid_stamps = stamps |> filter_valid_cross_stamps(nodes) |> Enum.count()

    if nb_valid_stamps >= required_validations do
      :reached
    else
      nb_remaining_stamps = Enum.count(nodes) - Enum.count(stamps)

      # If the remaining stamp to receive cannot reach the required validations we return an error
      if nb_valid_stamps + nb_remaining_stamps >= required_validations,
        do: :not_reached,
        else: :error
    end
  end

  @doc """
  Construct the proof of validation aggregating valid cross stamps signatures
  """
  @spec create(
          nodes :: ElectedNodes.t(),
          stamps :: list({Crypto.key(), CrossValidationStamp.t()})
        ) :: t()
  def create(%ElectedNodes{validation_nodes: nodes}, stamps) do
    valid_cross = filter_valid_cross_stamps(stamps, nodes)

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

    bitmask =
      Enum.reduce(valid_cross, <<>>, fn {from, _}, acc ->
        index = Enum.find_index(nodes, &(&1.first_public_key == from))
        Utils.set_bitstring_bit(acc, index)
      end)

    %__MODULE__{signature: aggregated_signature, nodes_bitmask: bitmask}
  end

  @doc """
  Returns the list of node that signed the proof of validation
  """
  @spec get_nodes(nodes :: ElectedNodes.t(), proof :: t()) :: list(Node.t())
  def get_nodes(%ElectedNodes{validation_nodes: nodes}, %__MODULE__{nodes_bitmask: bitmask}) do
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
  @spec valid?(
          nodes :: ElectedNodes.t(),
          proof :: t(),
          validation_stamp :: ValidationStamp.t()
        ) :: boolean()
  def valid?(
        elected_nodes = %ElectedNodes{
          required_validations: required_validations,
          validation_nodes: validation_nodes
        },
        proof = %__MODULE__{signature: signature},
        validation_stamp
      ) do
    signer_nodes = get_nodes(elected_nodes, proof)

    with true <- Enum.count(signer_nodes) >= required_validations,
         true <- signer_nodes |> MapSet.new() |> MapSet.subset?(MapSet.new(validation_nodes)) do
      aggregated_public_key =
        signer_nodes
        |> Enum.map(& &1.mining_public_key)
        |> Crypto.aggregate_mining_public_keys()

      raw_data = CrossValidationStamp.get_raw_data_to_sign(validation_stamp, [])

      Crypto.verify?(signature, raw_data, aggregated_public_key)
    else
      _ -> false
    end
  end

  defp filter_valid_cross_stamps(stamps, validation_nodes) do
    Enum.filter(stamps, fn {from, %CrossValidationStamp{inconsistencies: inconsistencies}} ->
      Enum.empty?(inconsistencies) and Utils.key_in_node_list?(validation_nodes, from)
    end)
  end

  defp get_nb_required_validations(nodes) do
    %StorageConstraints{number_replicas: nb_replicas_fn} = Election.get_storage_constraints()
    nb_replicas_fn.(nodes)
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{version: version, signature: signature, nodes_bitmask: bitmask}) do
    <<version::8, signature::binary, bit_size(bitmask)::8, bitmask::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) do
    <<version::8, signature::binary-size(@bls_signature_size), bitmask_size::8,
      bitmask::bitstring-size(bitmask_size), rest::bitstring>> = bin

    {%__MODULE__{version: version, signature: signature, nodes_bitmask: bitmask}, rest}
  end

  @spec cast(nil | map() | t()) :: t()
  def cast(nil), do: nil
  def cast(proof = %__MODULE__{}), do: proof

  def cast(map = %{}) do
    %__MODULE__{signature: Map.get(map, :signature), nodes_bitmask: Map.get(map, :nodes_bitmask)}
  end
end
