defmodule Uniris.Election do
  @moduledoc """
  Uniris provides a random and rotating node election based on heuristic algorithms
  and constraints to ensure a fair distributed processing and data storage among its network.
  """

  alias Uniris.Crypto

  alias __MODULE__.Constraints
  alias __MODULE__.StorageConstraints
  alias __MODULE__.ValidationConstraints

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.Transaction

  @doc """
  Get the elected validation nodes for a given transaction and a list of nodes.

  Each nodes public key is rotated with the daily nonce
  to provide an unpredictable order yet reproducible.

  To achieve an unpredictable, global but locally executed, verifiable and reproducible
  election, each election is based on:
  - an unpredictable element: hash of transaction
  - an element known only by authorized nodes: daily nonce
  - an element difficult to predict: last public key of the node
  - the computation of the rotating keys

  Then each nodes selection is reduce via heuristic constraints
  - a minimum of distinct geographical zones to distributed globally the validations
  - require number of validation for the given transaction criticity
  (ie: sum of UCO to transfer - a high UCO transfer will require a high number of validations)

  """
  @spec validation_nodes(Transaction.pending()) :: [Node.t()]
  def validation_nodes(tx = %Transaction{}) do
    # Evaluate heuristics constraints
    %ValidationConstraints{
      validation_number: validation_number_fun,
      min_geo_patch: min_geo_patch_fun
    } = Constraints.for_validation()

    min_geo_patch = min_geo_patch_fun.()
    nb_validations = validation_number_fun.(tx)

    tx_hash =
      tx
      |> Transaction.serialize()
      |> Crypto.hash()

    P2P.list_nodes()
    |> Enum.filter(& &1.ready?)
    |> Enum.filter(& &1.available?)
    |> Enum.filter(& &1.authorized?)
    |> sort_nodes_by_key_rotation(
      :last_public_key,
      :daily_nonce,
      tx_hash
    )
    |> do_validation_nodes(nb_validations, min_geo_patch)
  end

  defp do_validation_nodes(nodes, nb_validations, _) when length(nodes) < nb_validations,
    do: nodes

  defp do_validation_nodes(nodes, nb_validations, min_geo_patch) do
    nodes
    |> reduce_validation_node_election(
      nb_validations: nb_validations,
      min_geo_patch: min_geo_patch
    )
    |> case do
      elected_nodes when length(elected_nodes) >= nb_validations ->
        elected_nodes

      _ ->
        nodes
    end
  end

  defp reduce_validation_node_election(nodes, constraints, acc \\ %{nodes: [], zones: []})

  defp reduce_validation_node_election(
         _,
         [nb_validations: nb_validations, min_geo_patch: min_geo_patch],
         %{zones: zones, nodes: nodes}
       )
       when length(zones) > min_geo_patch and length(nodes) > nb_validations do
    nodes
  end

  defp reduce_validation_node_election(
         [node | rest_nodes],
         constraints,
         acc = %{zones: zones}
       ) do
    case Enum.find(zones, &(&1 == node.geo_patch)) do
      nil ->
        reduce_validation_node_election(
          rest_nodes,
          constraints,
          acc
          |> Map.update!(:nodes, &(&1 ++ [node]))
          |> Map.update!(:zones, &(&1 ++ [node.geo_patch]))
        )

      _ ->
        reduce_validation_node_election(rest_nodes, constraints, acc)
    end
  end

  defp reduce_validation_node_election([], _, %{nodes: nodes}), do: nodes

  @doc """
  Get the elected storage nodes for a given transaction address and a list of nodes.

  Each nodes first public key is rotated with the storage nonce and the transaction address
  to provide an reproducible list of nodes ordered.

  To perform the election, the rotating algorithm is based on:
  - the transaction address
  - an stable known element: storage nonce
  - the first public key of each node
  - the computation of the rotating keys

  From this sorted nodes, a selection is made by reducing it via heuristic constraints:
  - a require number of storage replicas from the given availability of the nodes
  - a minimum of distinct geographical zones to distributed globally the validations
  - a minimum avergage availability by geographical zones

  For a validation and mining perspective the storage election can be restricted
  to the only authorized nodes to ensure security
  """
  @spec storage_nodes(address :: binary()) :: [Node.t()]
  def storage_nodes(address, nodes \\ Enum.filter(P2P.list_nodes(), & &1.ready?))
      when is_binary(address) and is_list(nodes) do
    do_storage_nodes(address, nodes)
  end

  defp do_storage_nodes(_, []), do: []

  defp do_storage_nodes(address, nodes) do
    # Evaluate heuristics constraints
    %StorageConstraints{
      number_replicas: nb_replicas_fun,
      min_geo_patch: min_geo_patch_fun,
      min_geo_patch_avg_availability: min_geo_patch_avg_availability_fun
    } = Constraints.for_storage()

    nb_replicas = nb_replicas_fun.(nodes)
    min_geo_patch = min_geo_patch_fun.()
    min_geo_patch_avg_availability = min_geo_patch_avg_availability_fun.()

    nodes
    |> sort_nodes_by_key_rotation(
      :first_public_key,
      :storage_nonce,
      address
    )
    |> Enum.filter(& &1.available?)
    |> reduce_storage_node_election(
      nb_replicas: nb_replicas,
      min_geo_patch: min_geo_patch,
      min_geo_patch_avg_availability: min_geo_patch_avg_availability
    )
  end

  defp reduce_storage_node_election(nodes, constraints, acc \\ %{zones: %{}, nodes: []})

  defp reduce_storage_node_election(
         [node | rest_nodes],
         constraints = [
           nb_replicas: nb_replicas,
           min_geo_patch: min_geo_patch,
           min_geo_patch_avg_availability: min_geo_patch_avg_availability
         ],
         acc = %{nodes: nodes, zones: zones}
       ) do
    sufficient_zones =
      Enum.count(zones, fn {_, cumul} -> cumul >= min_geo_patch_avg_availability end)

    if sufficient_zones >= min_geo_patch and length(nodes) >= nb_replicas do
      nodes
    else
      reduce_storage_node_election(
        rest_nodes,
        constraints,
        acc
        |> Map.update!(:nodes, &(&1 ++ [node]))
        |> Map.update!(:zones, fn z ->
          Map.update(
            z,
            node.geo_patch,
            node.average_availability,
            &(&1 + node.average_availability)
          )
        end)
      )
    end
  end

  defp reduce_storage_node_election([], _, %{nodes: nodes}), do: nodes

  @doc """
  Provide an unpredictable and reproducible list of allowed nodes using a rotating key algorithm
  aims to get a scheduling to be able to find autonomously the validation or storages node involved.

  Each node public key is rotated through a cryptographic operations involving
  node public key, a nonce and a dynamic information such as transaction content or hash
  This rotated key acts as sort mechanism to produce a fair node election

  It's required the daily nonce or the storage nonce is loaded in the Crypto keystore
  """
  @spec sort_nodes_by_key_rotation(
          nodes :: list(Node.t()),
          node_key :: :first_public_key | :last_public_key,
          nonce_type :: :daily_nonce | :storage_nonce,
          hash :: binary()
        ) :: list(Node.t())
  def sort_nodes_by_key_rotation([], _, _, _), do: []

  def sort_nodes_by_key_rotation(nodes, key, nonce_type, hash)
      when is_list(nodes) and key in [:first_public_key, :last_public_key] and
             nonce_type in [:daily_nonce, :storage_nonce] and is_binary(hash) do
    nodes
    |> Enum.map(fn n ->
      rotated_key = do_hash(nonce_type, [Map.get(n, key), hash])
      {rotated_key, n}
    end)
    |> Enum.sort_by(fn {rotated_key, _} -> rotated_key end)
    |> Enum.map(fn {_, n} -> n end)
  end

  @spec do_hash(:daily_nonce | :storage_nonce, iodata()) :: binary()
  defp do_hash(:daily_nonce, data) do
    Crypto.hash_with_daily_nonce(data)
  end

  defp do_hash(:storage_nonce, data) do
    Crypto.hash_with_storage_nonce(data)
  end

  @doc """
  Return the actual constraints for the transaction validation
  """
  @spec validation_constraints() :: ValidationConstraints.t()
  def validation_constraints do
    Constraints.for_validation()
  end
end
