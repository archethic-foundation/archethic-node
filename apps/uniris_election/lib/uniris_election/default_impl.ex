defmodule UnirisElection.DefaultImpl do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisCrypto, as: Crypto
  alias UnirisElection.HeuristicConstraints, as: Constraints

  @behaviour UnirisElection.Impl

  @impl true
  @spec validation_nodes(
          UnirisChain.Transaction.pending(),
          [Node.t()],
          binary,
          constraints :: [
            min_geo_patch: (() -> non_neg_integer()),
            validation_number: (Transaction.pending() -> non_neg_integer())
          ]
        ) :: [Node.t()]
  def validation_nodes(
        tx = %Transaction{},
        nodes,
        daily_nonce,
        constraints \\ [
          min_geo_patch: fn -> Constraints.min_validation_geo_patch() end,
          validation_number: fn tx = %Transaction{} -> Constraints.validation_number(tx) end
        ]
      )
      when is_binary(daily_nonce) and is_list(nodes) and length(nodes) >= 5 do
    # Evaluate heuristics constraints
    min_geo_patch = Keyword.get(constraints, :min_geo_patch).()
    nb_validations = Keyword.get(constraints, :validation_number).(tx)

    nodes
    |> sort_nodes_by_key_rotation(:last_public_key, daily_nonce, Crypto.hash(tx))
    |> Enum.filter(&(&1.availability == 1))
    |> case do
      nodes when length(nodes) < nb_validations ->
        {:error, :unsufficient_network}

      nodes ->
        nodes
        |> Enum.reduce_while(%{nodes: [], zones: []}, fn n, acc ->
          reduce_validation_node_election(n, acc,
            nb_validations: nb_validations,
            min_geo_patch: min_geo_patch
          )
        end)
        |> Map.get(:nodes)
        |> case do
          elected_nodes when length(elected_nodes) < nb_validations ->
            {:error, :unsufficient_network}

          elected_nodes ->
            elected_nodes
        end
    end
  end

  @spec reduce_validation_node_election(
          Node.t(),
          %{zones: map(), nodes: list(Node.t())},
          nb_validations: non_neg_integer(),
          min_geo_patch: non_neg_integer()
        ) :: %{zones: list(), nodes: list(Node.t())}
  defp reduce_validation_node_election(
         n,
         acc,
         nb_validations: nb_validations,
         min_geo_patch: min_geo_patch
       ) do
    if length(acc.zones) >= min_geo_patch and length(acc.nodes) >= nb_validations do
      {:halt, acc}
    else
      top_geo_patch = String.first(n.geo_patch)

      case Enum.find(acc.zones, &(&1 == top_geo_patch)) do
        nil ->
          {:cont,
           acc
           |> Map.update!(:nodes, &(&1 ++ [n]))
           |> Map.update!(:zones, &(&1 ++ [top_geo_patch]))}

        _ ->
          {:cont, acc}
      end
    end
  end

  @impl true
  @spec storage_nodes(
          binary(),
          [Node.t()],
          binary(),
          constraints :: [
            min_geo_patch: (() -> non_neg_integer()),
            min_geo_patch_avg_availability: (() -> non_neg_integer()),
            number_replicas: (nonempty_list(Node.t()) -> non_neg_integer())
          ]
        ) :: [Node.t()]
  def storage_nodes(
        address,
        nodes,
        storage_nonce,
        constraints \\ [
          min_geo_patch: fn -> Constraints.min_storage_geo_patch() end,
          min_geo_patch_avg_availability: fn ->
            Constraints.min_storage_geo_patch_avg_availability()
          end,
          number_replicas: fn nodes -> Constraints.number_replicas(nodes) end
        ]
      )
      when is_binary(address) and is_binary(storage_nonce) and is_list(nodes) and
             is_list(constraints) do
    # Sort nodes using their first public key, the storage nonce and the transaction address
    sorted_nodes = sort_nodes_by_key_rotation(nodes, :first_public_key, storage_nonce, address)

    # Evaluate heuristics constraints
    nb_replicas = Keyword.get(constraints, :number_replicas).(sorted_nodes)
    min_geo_patch = Keyword.get(constraints, :min_geo_patch).()
    min_geo_patch_avg_availability = Keyword.get(constraints, :min_geo_patch_avg_availability).()

    sorted_nodes
    |> Enum.filter(&(&1.availability == 1))
    |> Enum.reduce_while(%{nodes: [], zones: %{}}, fn n, acc ->
      reduce_storage_node_election(n, acc,
        nb_replicas: nb_replicas,
        min_geo_patch: min_geo_patch,
        min_geo_patch_avg_availability: min_geo_patch_avg_availability
      )
    end)
    |> Map.get(:nodes)
  end

  @spec reduce_storage_node_election(
          Node.t(),
          %{zones: map(), nodes: nonempty_list(Node.t())},
          nb_replicas: (nonempty_list(Node.t()) -> non_neg_integer()),
          min_geo_patch: (() -> non_neg_integer()),
          min_geo_patch_avg_availability: (() -> non_neg_integer())
        ) :: %{zones: map(), nodes: list(Node.t())}
  defp reduce_storage_node_election(
         n,
         acc,
         _constraints = [
           nb_replicas: nb_replicas,
           min_geo_patch: min_geo_patch,
           min_geo_patch_avg_availability: min_geo_patch_avg_availability
         ]
       ) do
    sufficient_zones =
      Enum.count(acc.zones, fn {_, cumul} -> cumul >= min_geo_patch_avg_availability end)

    if sufficient_zones >= min_geo_patch and length(acc.nodes) >= nb_replicas do
      {:halt, acc}
    else
      {
        :cont,
        acc
        |> Map.update!(:nodes, &(&1 ++ [n]))
        |> Map.update!(:zones, fn z ->
          Map.update(
            z,
            String.first(n.geo_patch),
            n.average_availability,
            &(&1 + n.average_availability)
          )
        end)
      }
    end
  end

  # To provide an unpredictable and reproducible list of allowed nodes,
  # a rotating key algorithm aims to get a scheduling to be able to
  # find autonomously the validation or storages node involved.
  #
  # Each node public key is rotated through a cryptographic operations involving
  # node public key, a nonce and a dynamic information such as transaction content or hash
  # This rotated key acts as sort mechanism to produce a fair node election
  @spec sort_nodes_by_key_rotation(list(Node.t()), atom(), binary(), binary()) :: list(Node.t())
  defp sort_nodes_by_key_rotation(nodes, key, nonce, hash) do
    nodes
    |> Enum.map(fn n ->
      rotated_key = Crypto.hash(Map.get(n, key) <> "," <> nonce <> "," <> hash)
      {rotated_key, n}
    end)
    |> Enum.sort_by(fn {rotated_key, _} -> rotated_key end)
    |> Enum.map(fn {_, n} -> n end)
  end


end
