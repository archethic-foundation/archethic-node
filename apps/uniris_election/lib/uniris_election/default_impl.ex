defmodule UnirisElection.DefaultImpl do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisCrypto, as: Crypto
  alias __MODULE__.HeuristicConstraints, as: Constraints
  alias __MODULE__.HeuristicConstraints.Validation, as: ValidationConstraints
  alias __MODULE__.HeuristicConstraints.Storage, as: StorageConstraints
  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node

  @behaviour UnirisElection.Impl

  @impl true
  @spec validation_nodes(UnirisChain.Transaction.pending()) :: [Node.t()]
  def validation_nodes(tx = %Transaction{}) do
    # Evaluate heuristics constraints
    %ValidationConstraints{
      validation_number: validation_number_fun,
      min_geo_patch: min_geo_patch_fun
    } = Constraints.for_validation()

    min_geo_patch = min_geo_patch_fun.()
    nb_validations = validation_number_fun.(tx)

    nodes =
      P2P.list_nodes()
      |> Enum.filter(& &1.authorized?)
      |> sort_nodes_by_key_rotation(
        :last_public_key,
        :daily_nonce,
        Crypto.hash(tx)
      )

    if length(nodes) < nb_validations do
      nodes
    else
      nodes
      |> Enum.filter(&(&1.availability == 1))
      |> reduce_validation_node_election(
        nb_validations: nb_validations,
        min_geo_patch: min_geo_patch
      )
      |> case do
        elected_nodes when length(elected_nodes) >= nb_validations ->
          elected_nodes
      end
    end
  end

  @spec reduce_validation_node_election(
          list(Node.t()),
          constraints :: [
            nb_validations: non_neg_integer(),
            min_geo_patch: non_neg_integer()
          ],
          acc :: %{zones: list(char()), nodes: list(Node.t())}
        ) :: %{zones: list(), nodes: list(Node.t())}
  defp reduce_validation_node_election(nodes, constraints, acc \\ %{nodes: [], zones: []})

  defp reduce_validation_node_election(
         [node | rest_nodes],
         constraints = [nb_validations: nb_validations, min_geo_patch: min_geo_patch],
         acc = %{zones: zones, nodes: nodes}
       ) do
    if length(zones) > min_geo_patch and length(nodes) > nb_validations do
      nodes
    else
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
  end

  defp reduce_validation_node_election([], _, %{nodes: nodes}), do: nodes

  @impl true
  @spec storage_nodes(binary(), boolean()) :: [Node.t()]
  def storage_nodes(address, only_authorized?) when is_binary(address) do
    # Evaluate heuristics constraints
    %StorageConstraints{
      number_replicas: nb_replicas_fun,
      min_geo_patch: min_geo_patch_fun,
      min_geo_patch_avg_availability: min_geo_patch_avg_availability_fun
    } = Constraints.for_storage()

    nodes = if only_authorized? do
      Enum.filter(P2P.list_nodes(), &(&1.authorized?))
    else
      P2P.list_nodes()
    end

    nb_replicas = nb_replicas_fun.(nodes)
    min_geo_patch = min_geo_patch_fun.()
    min_geo_patch_avg_availability = min_geo_patch_avg_availability_fun.()

    nodes
    |> sort_nodes_by_key_rotation(
      :first_public_key,
      :storage_nonce,
      address
    )
    |> Enum.filter(&(&1.availability == 1))
    |> reduce_storage_node_election(
      nb_replicas: nb_replicas,
      min_geo_patch: min_geo_patch,
      min_geo_patch_avg_availability: min_geo_patch_avg_availability
    )
  end

  @spec reduce_storage_node_election(
          Node.t(),
          constraints :: [
            nb_replicas: (nonempty_list(Node.t()) -> non_neg_integer()),
            min_geo_patch: (() -> non_neg_integer()),
            min_geo_patch_avg_availability: (() -> non_neg_integer())
          ],
          %{zones: map(), nodes: nonempty_list(Node.t())}
        ) :: %{zones: map(), nodes: list(Node.t())}
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
            String.first(node.geo_patch),
            node.average_availability,
            &(&1 + node.average_availability)
          )
        end)
      )
    end
  end

  defp reduce_storage_node_election([], _, %{nodes: nodes}), do: nodes

  # To provide an unpredictable and reproducible list of allowed nodes,
  # a rotating key algorithm aims to get a scheduling to be able to
  # find autonomously the validation or storages node involved.
  #
  # Each node public key is rotated through a cryptographic operations involving
  # node public key, a nonce and a dynamic information such as transaction content or hash
  # This rotated key acts as sort mechanism to produce a fair node election
  @spec sort_nodes_by_key_rotation(
          list(Node.t()),
          atom(),
          :daily_nonce | :storage_nonce,
          binary()
        ) :: list(Node.t())
  defp sort_nodes_by_key_rotation(nodes, key, nonce_type, hash) do
    nodes
    |> Enum.map(fn n ->
      rotated_key = do_hash(nonce_type, [Map.get(n, key), hash])
      {rotated_key, n}
    end)
    |> Enum.sort_by(fn {rotated_key, _} -> rotated_key end)
    |> Enum.map(fn {_, n} -> n end)
  end

  defp do_hash(:daily_nonce, data) do
    Crypto.hash_with_daily_nonce(data)
  end

  defp do_hash(:storage_nonce, data) do
    Crypto.hash_with_storage_nonce(data)
  end

end
