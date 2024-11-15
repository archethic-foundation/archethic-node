defmodule Archethic.TransactionChain.Transaction.ProofOfReplication do
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

  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

  alias __MODULE__.ElectedNodes
  alias __MODULE__.Signature

  @enforce_keys [:signature, :nodes_bitmask]
  defstruct [:signature, :nodes_bitmask, version: 1]

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          signature: binary(),
          nodes_bitmask: bitstring()
        }

  @bls_signature_size 96
  @signature_threshold 0.75

  defmodule ElectedNodes do
    @moduledoc """
    Struct holding sorted storage nodes elected for the transaction
    and the required number of validations
    """
    alias Archethic.P2P.Node

    @enforce_keys [:required_signatures, :storage_nodes]
    defstruct [:required_signatures, storage_nodes: []]

    @type t :: %__MODULE__{
            required_signatures: non_neg_integer(),
            storage_nodes: list(Node.t())
          }
  end

  @doc """
  Returns the sorted list of nodes and the required number of storage nodes
  The input nodes list needs to be the authorized and available nodes at the time of the transaction
  """
  @spec get_election(nodes :: list(Node.t()), tx_address :: Crypto.prepended_hash()) ::
          ElectedNodes.t()
  def get_election(nodes, tx_address) do
    required_signatures = get_nb_required_signatures(nodes)
    storage_nodes = Election.storage_nodes(tx_address, nodes)

    %ElectedNodes{
      required_signatures: required_signatures,
      storage_nodes: Enum.sort_by(storage_nodes, & &1.first_public_key)
    }
  end

  @doc """
  Returns true if a node public key is part of the elected nodes
  """
  @spec elected_node?(nodes :: ElectedNodes.t(), signature :: Signature.t()) :: boolean()
  def elected_node?(
        %ElectedNodes{storage_nodes: nodes},
        %Signature{node_public_key: node_public_key}
      ),
      do: Utils.key_in_node_list?(nodes, node_public_key)

  @doc """
  Determines if enough signatures have been received to create the aggregated signature
  Returns
    - :reached if enough stamps are valid
    - :not_reached if not enough stamps received yet
  """
  @spec get_state(nodes :: ElectedNodes.t(), signatures :: list(Signature.t())) ::
          :reached | :not_reached
  def get_state(
        %ElectedNodes{required_signatures: required_signatures, storage_nodes: nodes},
        signatures
      ) do
    nb_valid_signatures = signatures |> filter_elected_signatures(nodes) |> Enum.count()

    if nb_valid_signatures >= required_signatures, do: :reached, else: :not_reached
  end

  @doc """
  Construct the proof of replication aggregating signatures
  """
  @spec create(nodes :: ElectedNodes.t(), signatures :: list(Signature.t())) :: t()
  def create(%ElectedNodes{storage_nodes: nodes}, proof_signatures) do
    proof_signatures = filter_elected_signatures(proof_signatures, nodes)

    {public_keys, signatures} =
      Enum.reduce(
        proof_signatures,
        {[], []},
        fn %Signature{node_mining_key: key, signature: signature}, {public_keys, signatures} ->
          {[key | public_keys], [signature | signatures]}
        end
      )

    aggregated_signature = Crypto.aggregate_signatures(signatures, public_keys)

    bitmask =
      Enum.reduce(proof_signatures, <<>>, fn %Signature{node_public_key: key}, acc ->
        index = Enum.find_index(nodes, &(&1.first_public_key == key))
        Utils.set_bitstring_bit(acc, index)
      end)

    %__MODULE__{signature: aggregated_signature, nodes_bitmask: bitmask}
  end

  @doc """
  Returns the list of node that signed the proof of replication
  """
  @spec get_nodes(nodes :: ElectedNodes.t(), proof :: t()) :: list(Node.t())
  def get_nodes(%ElectedNodes{storage_nodes: nodes}, %__MODULE__{nodes_bitmask: bitmask}) do
    bitmask
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.filter(&(elem(&1, 0) == 1))
    |> Enum.map(fn {_, index} -> Enum.at(nodes, index) end)
  end

  @doc """
  Validate a proof of replication
  - Number of signatures reach the threshold
  - Aggregated signature is valid
  """
  @spec valid?(
          nodes :: ElectedNodes.t(),
          proof :: t(),
          transaction_summary :: TransactionSummary.t()
        ) :: boolean()
  def valid?(
        elected_nodes = %ElectedNodes{
          required_signatures: required_signatures,
          storage_nodes: storage_nodes
        },
        proof = %__MODULE__{signature: signature},
        transaction_summary
      ) do
    signer_nodes = get_nodes(elected_nodes, proof)

    with true <- Enum.count(signer_nodes) >= required_signatures,
         true <- signer_nodes |> MapSet.new() |> MapSet.subset?(MapSet.new(storage_nodes)) do
      aggregated_public_key =
        signer_nodes
        |> Enum.map(& &1.mining_public_key)
        |> Crypto.aggregate_mining_public_keys()

      raw_data = TransactionSummary.serialize(transaction_summary)

      Crypto.verify?(signature, raw_data, aggregated_public_key)
    else
      _ -> false
    end
  end

  defp filter_elected_signatures(signatures, storage_nodes) do
    Enum.filter(signatures, &Utils.key_in_node_list?(storage_nodes, &1.node_public_key))
  end

  defp get_nb_required_signatures(nodes) do
    %StorageConstraints{number_replicas: nb_replicas_fn} = Election.get_storage_constraints()
    election_nb = nb_replicas_fn.(nodes)
    ceil(election_nb * @signature_threshold)
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

  @spec to_map(elected_nodes :: ElectedNodes.t(), proof :: t()) :: nil | map()
  def to_map(elected_nodes = %ElectedNodes{}, proof) do
    node_public_keys = elected_nodes |> get_nodes(proof) |> Enum.map(& &1.first_public_key)
    %{signature: proof.signature, node_public_keys: node_public_keys}
  end

  def to_map(_, _), do: nil
end
