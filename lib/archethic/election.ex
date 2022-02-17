defmodule ArchEthic.Election do
  @moduledoc """
  Provides a random and rotating node election based on heuristic algorithms
  and constraints to ensure a fair distributed processing and data storage among its network.
  """

  alias ArchEthic.BeaconChain

  alias ArchEthic.Crypto

  alias __MODULE__.Constraints
  alias __MODULE__.StorageConstraints
  alias __MODULE__.ValidationConstraints

  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction

  alias ArchEthic.Utils

  @doc """
  Create a seed to sort the validation nodes. This will produce a proof for the election
  """
  @spec validation_nodes_election_seed_sorting(Transaction.t(), DateTime.t()) :: binary()
  def validation_nodes_election_seed_sorting(tx = %Transaction{}, timestamp = %DateTime{}) do
    tx_hash =
      tx
      |> Transaction.to_pending()
      |> Transaction.serialize()
      |> Crypto.hash()

    Crypto.sign_with_daily_nonce_key(tx_hash, timestamp)
  end

  @doc """
  Verify if a proof of election is valid according to transaction and the given public key
  """
  @spec valid_proof_of_election?(Transaction.t(), binary, Crypto.key()) :: boolean
  def valid_proof_of_election?(tx = %Transaction{}, proof_of_election, daily_nonce_public_key)
      when is_binary(proof_of_election) and is_binary(daily_nonce_public_key) do
    data =
      tx
      |> Transaction.to_pending()
      |> Transaction.serialize()
      |> Crypto.hash()

    Crypto.verify?(proof_of_election, data, daily_nonce_public_key)
  end

  @doc """
  Get the elected validation nodes for a given transaction and a list of nodes.

  Each nodes public key is rotated with the sorting seed
  to provide an unpredictable order yet reproducible.

  To achieve an unpredictable, global but locally executed, verifiable and reproducible
  election, each election is based on:
  - an unpredictable element: hash of transaction
  - an element known only by authorized nodes: daily nonce
  - an element difficult to predict: last public key of the node
  - the computation of the rotating keys

  Then each nodes selection is reduce via heuristic constraints via `ValidationConstraints`

  ## Examples

      iex> %Transaction{
      ...>   address:
      ...>     <<0, 120, 195, 32, 77, 84, 215, 196, 116, 215, 56, 141, 40, 54, 226, 48, 66, 254, 119,
      ...>       11, 73, 77, 243, 125, 62, 94, 133, 67, 9, 253, 45, 134, 89>>,
      ...>   type: :transfer,
      ...>   data: %TransactionData{},
      ...>   previous_public_key:
      ...>     <<0, 239, 240, 90, 182, 66, 190, 68, 20, 250, 131, 83, 190, 29, 184, 177, 52, 166, 207,
      ...>       80, 193, 110, 57, 6, 199, 152, 184, 24, 178, 179, 11, 164, 150>>,
      ...>   previous_signature:
      ...>     <<200, 70, 0, 25, 105, 111, 15, 161, 146, 188, 100, 234, 147, 62, 127, 8, 152, 60, 66,
      ...>       169, 113, 255, 51, 112, 59, 200, 61, 63, 128, 228, 111, 104, 47, 15, 81, 185, 179, 36,
      ...>       59, 86, 171, 7, 138, 199, 203, 252, 50, 87, 160, 107, 119, 131, 121, 11, 239, 169, 99,
      ...>       203, 76, 159, 158, 243, 133, 133>>,
      ...>   origin_signature:
      ...>     <<162, 223, 100, 72, 17, 56, 99, 212, 78, 132, 166, 81, 127, 91, 214, 143, 221, 32, 106,
      ...>       189, 247, 64, 183, 27, 55, 142, 254, 72, 47, 215, 34, 108, 233, 55, 35, 94, 49, 165,
      ...>       180, 248, 229, 160, 229, 220, 191, 35, 80, 127, 213, 240, 195, 185, 165, 89, 172, 97,
      ...>       170, 217, 57, 254, 125, 127, 62, 169>>
      ...> }
      ...> |> Election.validation_nodes(
      ...>     "daily_nonce_proof",
      ...>     [
      ...>       %Node{last_public_key: "node1", geo_patch: "AAA"},
      ...>       %Node{last_public_key: "node2", geo_patch: "DEF"},
      ...>       %Node{last_public_key: "node3", geo_patch: "AA0"},
      ...>       %Node{last_public_key: "node4", geo_patch: "3AC"},
      ...>       %Node{last_public_key: "node5", geo_patch: "F10"},
      ...>       %Node{last_public_key: "node6", geo_patch: "ECA"}
      ...>     ],
      ...>     [
      ...>       %Node{last_public_key: "node10", geo_patch: "AAA"},
      ...>       %Node{last_public_key: "node11", geo_patch: "DEF"},
      ...>       %Node{last_public_key: "node13", geo_patch: "AA0"},
      ...>       %Node{last_public_key: "node4", geo_patch: "3AC"},
      ...>       %Node{last_public_key: "node8", geo_patch: "F10"},
      ...>       %Node{last_public_key: "node9", geo_patch: "ECA"}
      ...>     ],
      ...>     %ValidationConstraints{ validation_number: fn _, 6 -> 3 end, min_geo_patch: fn -> 2 end }
      ...> )
      [
        %Node{last_public_key: "node6", geo_patch: "ECA"},
        %Node{last_public_key: "node2", geo_patch: "DEF"},
        %Node{last_public_key: "node3", geo_patch: "AA0"},
        %Node{last_public_key: "node5", geo_patch: "F10"},
      ]
  """
  @spec validation_nodes(
          pending_transaction :: Transaction.t(),
          sorting_seed :: binary(),
          authorized_nodes :: list(Node.t()),
          storage_nodes :: list(Node.t()),
          constraints :: ValidationConstraints.t()
        ) :: list(Node.t())
  def validation_nodes(
        tx = %Transaction{},
        sorting_seed,
        authorized_nodes,
        storage_nodes,
        %ValidationConstraints{
          validation_number: validation_number_fun,
          min_geo_patch: min_geo_patch_fun
        } \\ ValidationConstraints.new()
      )
      when is_binary(sorting_seed) and is_list(authorized_nodes) and is_list(storage_nodes) do
    start = System.monotonic_time()

    # Evaluate validation constraints
    nb_validations = validation_number_fun.(tx, length(authorized_nodes))
    min_geo_patch = min_geo_patch_fun.()

    nodes =
      if length(authorized_nodes) <= nb_validations do
        authorized_nodes
      else
        do_validation_node_election(
          authorized_nodes,
          tx,
          sorting_seed,
          nb_validations,
          min_geo_patch,
          storage_nodes
        )
      end

    :telemetry.execute(
      [:archethic, :election, :validation_nodes],
      %{
        duration: System.monotonic_time() - start
      },
      %{nb_nodes: length(authorized_nodes)}
    )

    nodes
  end

  defp do_validation_node_election(
         authorized_nodes,
         tx,
         sorting_seed,
         nb_validations,
         min_geo_patch,
         storage_nodes
       ) do
    tx_hash =
      tx
      |> Transaction.to_pending()
      |> Transaction.serialize()
      |> Crypto.hash()

    authorized_nodes
    |> sort_validation_nodes_by_key_rotation(sorting_seed, tx_hash)
    |> Enum.reduce_while(
      %{nb_nodes: 0, nodes: [], zones: MapSet.new()},
      fn node = %Node{geo_patch: geo_patch, last_public_key: last_public_key}, acc ->
        if validation_constraints_satisfied?(
             nb_validations,
             min_geo_patch,
             acc.nb_nodes,
             acc.zones
           ) do
          {:halt, acc}
        else
          # Discard node in the first place if it's already a storage node and
          # if another node already present in the geo zone to ensure geo distribution of validations
          # Then if requires the node may be elected during a refining operation
          # to ensure the require number of validations

          cond do
            Utils.key_in_node_list?(storage_nodes, last_public_key) ->
              {:cont, acc}

            MapSet.member?(acc.zones, String.first(geo_patch)) ->
              {:cont, acc}

            true ->
              new_acc =
                acc
                |> Map.update!(:nb_nodes, &(&1 + 1))
                |> Map.update!(:nodes, &[node | &1])
                |> Map.update!(:zones, &MapSet.put(&1, String.first(geo_patch)))

              {:cont, new_acc}
          end
        end
      end
    )
    |> Map.get(:nodes)
    |> Enum.reverse()
    |> refine_necessary_nodes(authorized_nodes, nb_validations)
  end

  defp validation_constraints_satisfied?(nb_validations, min_geo_patch, nb_nodes, zones) do
    MapSet.size(zones) > min_geo_patch and nb_nodes > nb_validations
  end

  defp refine_necessary_nodes(selected_nodes, authorized_nodes, nb_validations) do
    rest_nodes = authorized_nodes -- selected_nodes

    if length(selected_nodes) < nb_validations do
      selected_nodes ++ Enum.take(rest_nodes, nb_validations - length(selected_nodes))
    else
      selected_nodes
    end
  end

  @doc """
  Get the elected storage nodes for a given transaction address and a list of nodes.

  Each nodes first public key is rotated with the storage nonce and the transaction address
  to provide an reproducible list of nodes ordered.

  To perform the election, the rotating algorithm is based on:
  - the transaction address
  - an stable known element: storage nonce
  - the first public key of each node
  - the computation of the rotating keys

  From this sorted nodes, a selection is made by reducing it via heuristic constraints via `StorageConstraints`
  """
  @spec storage_nodes(address :: binary(), nodes :: list(Node.t()), StorageConstraints.t()) ::
          list(Node.t())
  def storage_nodes(_address, _nodes, constraints \\ StorageConstraints.new())
  def storage_nodes(_, [], _), do: []

  def storage_nodes(
        address,
        nodes,
        %StorageConstraints{
          number_replicas: number_replicas_fun,
          min_geo_patch_average_availability: min_geo_patch_avg_availability_fun,
          min_geo_patch: min_geo_patch_fun
        }
      )
      when is_binary(address) and is_list(nodes) do
    start = System.monotonic_time()

    # Evaluate the storage election constraints

    nb_replicas = number_replicas_fun.(nodes)
    min_geo_patch_avg_availability = min_geo_patch_avg_availability_fun.()
    min_geo_patch = min_geo_patch_fun.()

    storage_nodes =
      nodes
      |> Enum.sort_by(&Map.get(&1, :authorized?), :desc)
      |> sort_storage_nodes_by_key_rotation(address)
      |> Enum.reduce_while(
        %{
          nb_nodes: 0,
          zones: %{},
          nodes: [],
          nb_replicas: nb_replicas,
          min_geo_patch: min_geo_patch,
          min_geo_patch_avg_availability: min_geo_patch_avg_availability
        },
        &reduce_storage_nodes/2
      )
      |> Map.get(:nodes)
      |> Enum.reverse()

    :telemetry.execute(
      [:archethic, :election, :storage_nodes],
      %{duration: System.monotonic_time() - start},
      %{nb_nodes: length(nodes)}
    )

    storage_nodes
  end

  defp reduce_storage_nodes(
         node = %Node{
           geo_patch: geo_patch,
           average_availability: avg_availability
         },
         acc
       ) do
    if storage_constraints_satisfied?(acc) do
      {:halt, acc}
    else
      new_acc =
        acc
        |> Map.update!(:zones, fn zones ->
          Map.update(
            zones,
            String.first(geo_patch),
            avg_availability,
            &(&1 + avg_availability)
          )
        end)
        |> Map.update!(:nb_nodes, &(&1 + 1))
        |> Map.update!(:nodes, &[node | &1])

      {:cont, new_acc}
    end
  end

  defp storage_constraints_satisfied?(%{
         min_geo_patch: min_geo_patch,
         min_geo_patch_avg_availability: min_geo_patch_avg_availability,
         nb_replicas: nb_replicas,
         nb_nodes: nb_nodes,
         zones: zones
       }) do
    length(Map.keys(zones)) >= min_geo_patch and
      Enum.all?(zones, fn {_, avg_availability} ->
        avg_availability >= min_geo_patch_avg_availability
      end) and
      nb_nodes >= nb_replicas
  end

  # Provide an unpredictable and reproducible list of allowed nodes using a rotating key algorithm
  # aims to get a scheduling to be able to find autonomously the validation or storages node involved.

  # Each node public key is rotated through a cryptographic operations involving
  # node public key, a nonce and a dynamic information such as transaction content or hash
  # This rotated key acts as sort mechanism to produce a fair node election

  # It requires the daily nonce or the storage nonce to be loaded in the Crypto keystore
  defp sort_validation_nodes_by_key_rotation(nodes, sorting_seed, hash) do
    nodes
    |> Stream.map(fn node = %Node{last_public_key: last_public_key} ->
      rotated_key = Crypto.hash([last_public_key, hash, sorting_seed])
      {rotated_key, node}
    end)
    |> Enum.sort_by(fn {rotated_key, _} -> rotated_key end)
    |> Enum.map(fn {_, n} -> n end)
  end

  defp sort_storage_nodes_by_key_rotation(nodes, hash) do
    nodes
    |> Stream.map(fn node = %Node{first_public_key: last_public_key} ->
      rotated_key = Crypto.hash_with_storage_nonce([last_public_key, hash])
      {rotated_key, node}
    end)
    |> Enum.sort_by(fn {rotated_key, _} -> rotated_key end)
    |> Enum.map(fn {_, n} -> n end)
  end

  @doc """
  Return the actual constraints for the transaction validation
  """
  @spec get_validation_constraints() :: ValidationConstraints.t()
  defdelegate get_validation_constraints, to: Constraints

  @doc """
  Set the new validation constraints
  """
  @spec set_validation_constraints(ValidationConstraints.t()) :: :ok
  defdelegate set_validation_constraints(constraints), to: Constraints

  @doc """
  Return the actual constraints for the transaction storage
  """
  @spec get_storage_constraints() :: StorageConstraints.t()
  defdelegate get_storage_constraints(), to: Constraints

  @doc """
  Set the new storage constraints
  """
  @spec set_storage_constraints(StorageConstraints.t()) :: :ok
  defdelegate set_storage_constraints(constraints), to: Constraints

  @doc """
  Find out the next authorized nodes using the TPS from the previous to determine based
  on the active geo patches if we need to more node related to the network load.

  ## Examples

    # No need to add more validation nodes if the TPS is null

      iex> nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(0.0, nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true}
      ]

    # Need to add more validation nodes if the TPS is less than 1

      iex> nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(0.0243, nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
        %Node{first_public_key: "key3", geo_patch: "A34"},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true},
        %Node{first_public_key: "key5", geo_patch: "D34"}
      ]

    # No need to add more validation nodes if the TPS is enough regarding the active patches

      iex> nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(100.0, nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true}
      ]

    # With a higher TPS we need more node to cover the transaction mining

      iex> nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(1000.0, nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true},
        %Node{first_public_key: "key3", geo_patch: "A34"},
        %Node{first_public_key: "key5", geo_patch: "D34"}
      ]
  """
  @spec next_authorized_nodes(float(), list(Node.t())) ::
          list(Node.t())
  def next_authorized_nodes(0.0, nodes), do: Enum.filter(nodes, & &1.authorized?)

  def next_authorized_nodes(previous_tps, nodes)
      when is_float(previous_tps) and previous_tps < 1.0,
      do: nodes

  def next_authorized_nodes(previous_tps, nodes)
      when is_float(previous_tps) and previous_tps >= 1.0 and is_list(nodes) do
    authorized_nodes = Enum.filter(nodes, & &1.authorized?)

    case nb_of_authorized_nodes_to_add(previous_tps, nodes) do
      0 ->
        authorized_nodes

      nb_nodes_to_add ->
        nodes
        |> Enum.filter(&(!&1.authorized?))
        |> Enum.group_by(& &1.geo_patch)
        |> Enum.reduce(authorized_nodes, fn {_, nodes}, acc ->
          acc ++ Enum.take(nodes, nb_nodes_to_add)
        end)
    end
  end

  defp nb_of_authorized_nodes_to_add(previous_tps, nodes) do
    nb_active_patches =
      nodes
      |> Enum.filter(& &1.authorized?)
      |> Enum.map(&String.slice(&1.geo_patch, 0, 2))
      |> Enum.uniq()
      |> length()

    tps_by_patch = previous_tps / nb_active_patches

    nb_nodes_to_add = tps_by_patch / (100 * 0.6)

    if nb_nodes_to_add < 1 do
      0
    else
      ceil(nb_nodes_to_add)
    end
  end

  @doc """
  Return the initiator of the node shared secrets transaction
  """
  @spec node_shared_secrets_initiator(address :: binary(), authorized_nodes :: list(Node.t())) ::
          Node.t()
  def node_shared_secrets_initiator(address, nodes, constraints \\ StorageConstraints.new())
      when is_list(nodes) do
    # Determine if the current node is in charge to the send the new transaction
    [initiator = %Node{} | _] = storage_nodes(address, nodes, constraints)
    initiator
  end

  @doc """
  List all the I/O storage nodes from a ledger operations movements
  """
  @spec io_storage_nodes(
          movements_addresses :: list(binary()),
          nodes :: list(Node.t()),
          constraints :: StorageConstraints.t()
        ) :: list(Node.t())
  def io_storage_nodes(
        movements_addresses,
        nodes,
        storage_constraints \\ StorageConstraints.new()
      ) do
    movements_addresses
    |> Stream.map(&storage_nodes(&1, nodes, storage_constraints))
    |> Stream.flat_map(& &1)
    |> Enum.uniq_by(& &1.first_public_key)
  end

  @doc """
  List all the beacon storage nodes based on transaction
  """
  @spec beacon_storage_nodes(
          subset :: binary(),
          date :: DateTime.t(),
          nodes :: list(Node.t()),
          constraints :: StorageConstraints.t()
        ) :: list(Node.t())
  def beacon_storage_nodes(
        subset,
        date = %DateTime{},
        nodes,
        storage_constraints = %StorageConstraints{} \\ StorageConstraints.new()
      )
      when is_binary(subset) and is_list(nodes) do
    subset
    |> BeaconChain.summary_transaction_address(date)
    |> storage_nodes(nodes, storage_constraints)
  end
end
