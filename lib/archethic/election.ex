defmodule Archethic.Election do
  @moduledoc """
  Provides a random and rotating node election based on heuristic algorithms
  and constraints to ensure a fair distributed processing and data storage among its network.
  """

  alias Archethic.Crypto

  alias __MODULE__.Constraints
  alias __MODULE__.StorageConstraints
  alias __MODULE__.ValidationConstraints
  alias __MODULE__.HypergeometricDistribution

  alias Archethic.P2P.Node

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.Utils

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
      ...>     %ValidationConstraints{ validation_number: fn _, 6 -> 3 end, min_geo_patch: fn -> 3 end }
      ...> )
      [
        %Node{last_public_key: "node6", geo_patch: "ECA"},
        %Node{last_public_key: "node4", geo_patch: "3AC"},
        %Node{last_public_key: "node5", geo_patch: "F10"}
      ]
  """
  @spec validation_nodes(
          pending_transaction :: Transaction.t(),
          sorting_seed :: binary(),
          authorized_nodes :: list(Node.t()),
          constraints :: ValidationConstraints.t(),
          iteration :: pos_integer()
        ) :: list(Node.t())
  def validation_nodes(
        tx = %Transaction{},
        sorting_seed,
        authorized_nodes,
        %ValidationConstraints{
          validation_number: validation_number_fun,
          min_geo_patch: min_geo_patch_fun
        } \\ ValidationConstraints.new(),
        iteration \\ 1
      )
      when is_binary(sorting_seed) and is_list(authorized_nodes) and is_number(iteration) and
             iteration > 0 and iteration <= 3 do
    start = System.monotonic_time()

    nb_authorized_nodes = length(authorized_nodes)

    # Evaluate validation constraints
    nb_validations =
      min(
        hypergeometric_distribution(nb_authorized_nodes),
        validation_number_fun.(tx, nb_authorized_nodes)
      )

    min_geo_patch = min_geo_patch_fun.()

    sorted_nodes = sort_validation_nodes(authorized_nodes, tx, sorting_seed)

    nodes =
      if length(authorized_nodes) <= nb_validations do
        sorted_nodes
      else
        do_validation_node_election(
          sorted_nodes,
          nb_validations,
          min_geo_patch,
          iteration
        )
      end

    :telemetry.execute(
      [:archethic, :election, :validation_nodes],
      %{
        duration: System.monotonic_time() - start
      },
      %{nb_nodes: length(nodes)}
    )

    nodes
  end

  defp do_validation_node_election(
         sorted_nodes,
         nb_validations,
         min_geo_patch,
         iteration
       ) do
    Enum.reduce_while(
      sorted_nodes,
      %{nb_nodes: 0, nodes: [], zones: MapSet.new()},
      fn node = %Node{geo_patch: geo_patch}, acc ->
        # Check if the conditions are satisfied
        if MapSet.size(acc.zones) >= min_geo_patch and acc.nb_nodes >= nb_validations do
          {:halt, acc}
        else
          # Discard node in the first place if it's already a storage node or
          # if another node already present in the geo zone to ensure geo distribution of validations

          # Depending on the election iteration, we extend the geo patch acceptance aria
          # to include more nodes in the same geo  in case of unavailability
          {zone, _} = String.split_at(geo_patch, iteration)

          if MapSet.member?(acc.zones, zone) do
            {:cont, acc}
          else
            new_acc =
              acc
              |> Map.update!(:nb_nodes, &(&1 + 1))
              |> Map.update!(:nodes, &[node | &1])
              |> Map.update!(:zones, &MapSet.put(&1, zone))

            {:cont, new_acc}
          end
        end
      end
    )
    |> Map.get(:nodes)
    |> Enum.reverse()
  end

  @doc """
  Sort the validation nodes with the given sorting seed
  """
  @spec sort_validation_nodes(
          node_list :: list(Node.t()),
          transaction :: Transaction.t(),
          sorting_seed :: binary()
        ) :: list(Node.t())
  def sort_validation_nodes(node_list, tx, sorting_seed) do
    tx_hash =
      tx
      |> Transaction.to_pending()
      |> Transaction.serialize()
      |> Crypto.hash()

    sort_validation_nodes_by_key_rotation(node_list, sorting_seed, tx_hash)
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

    storage_nonce = Crypto.storage_nonce()

    storage_nodes =
      nodes
      |> sort_storage_nodes_by_key_rotation(address, storage_nonce)
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
    if nb_nodes >= nb_replicas do
      fullfilled_zones =
        Enum.filter(zones, fn {_, avg} -> avg >= min_geo_patch_avg_availability end)

      length(fullfilled_zones) >= min_geo_patch
    else
      false
    end
  end

  # Provide an unpredictable and reproducible list of allowed nodes using a rotating key algorithm
  # aims to get a scheduling to be able to find autonomously the validation or storages node involved.

  # Each node public key is rotated through a cryptographic operations involving
  # node public key, a nonce and a dynamic information such as transaction content or hash
  # This rotated key acts as sort mechanism to produce a fair node election

  # It requires the daily nonce or the storage nonce to be loaded in the Crypto keystore
  defp sort_validation_nodes_by_key_rotation(nodes, sorting_seed, hash) do
    nodes
    |> Stream.map(fn node = %Node{last_public_key: <<_::8, _::8, public_key::binary>>} ->
      rotated_key = :crypto.hash(:sha256, [public_key, hash, sorting_seed])
      {rotated_key, node}
    end)
    |> Enum.sort_by(fn {rotated_key, _} -> rotated_key end)
    |> Enum.map(fn {_, n} -> n end)
  end

  defp sort_storage_nodes_by_key_rotation(nodes, hash, storage_nonce) do
    nodes
    |> Stream.map(fn node = %Node{first_public_key: <<_::8, _::8, public_key::binary>>} ->
      rotated_key = :crypto.hash(:sha256, [public_key, hash, storage_nonce])
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

  We are keeping the previous authorized nodes because
  a previous authorized node becoming unauthorized signifies a ban
  as the network don't want this node to be part of the validation nodes

  Also for synchronization reason, we want an offline authorized nodes be able to retrieve
  the secrets to be able to rejoin the network with its full capacity

  But we are allowing new nodes to join if the network requirements (TPS, geographical distribution) allows it

  ## Examples

    # No need to add more validation nodes if the TPS is null

      iex> previous_authorized_nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
      ...> ]
      iex> candidate_nodes = [
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(0.0, candidate_nodes, previous_authorized_nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true}
      ]

    # Need to add more validation nodes if the TPS is less than 1

      iex> previous_authorized_nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
      ...> ]
      iex> candidate_nodes = [
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(0.0243, candidate_nodes, previous_authorized_nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
        %Node{first_public_key: "key3", geo_patch: "A34"},
        %Node{first_public_key: "key5", geo_patch: "D34"}
      ]

    # No need to add more validation nodes if the TPS is enough regarding the active patches

      iex> previous_authorized_nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
      ...> ]
      iex> candidate_nodes = [
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(100.0, candidate_nodes, previous_authorized_nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true}
      ]

   # With some previous authorized nodes not available, we are putting more nodes as it's needed

     iex> previous_authorized_nodes = [
     ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: false},
     ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
     ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
     ...> ]
     iex> candidate_nodes = [
     ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
     ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
     ...> ]
     iex> Election.next_authorized_nodes(100.0, candidate_nodes, previous_authorized_nodes)
     [
       %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: false},
       %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
       %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
       %Node{first_public_key: "key3", geo_patch: "A34"},
       %Node{first_public_key: "key5", geo_patch: "D34"}
     ]


    # With a higher TPS we need more node to cover the transaction mining

      iex> previous_authorized_nodes = [
      ...>   %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
      ...>   %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
      ...> ]
      iex> candidate_nodes = [
      ...>   %Node{first_public_key: "key3", geo_patch: "A34"},
      ...>   %Node{first_public_key: "key5", geo_patch: "D34"}
      ...> ]
      iex> Election.next_authorized_nodes(1000.0, candidate_nodes, previous_authorized_nodes)
      [
        %Node{first_public_key: "key1", geo_patch: "AAA", authorized?: true, available?: true},
        %Node{first_public_key: "key2", geo_patch: "B34", authorized?: true, available?: true},
        %Node{first_public_key: "key4", geo_patch: "F34", authorized?: true, available?: true},
        %Node{first_public_key: "key3", geo_patch: "A34"},
        %Node{first_public_key: "key5", geo_patch: "D34"}
      ]
  """
  def next_authorized_nodes(0.0, _candidates, previous_authorized_nodes) do
    # If the TPS is null then we don't add new validation nodes
    previous_authorized_nodes
  end

  def next_authorized_nodes(previous_tps, candidate_nodes, previous_authorized_nodes)
      when is_float(previous_tps) and previous_tps < 1.0 do
    # If the TPS is too low, we are accepting nodes
    previous_authorized_nodes ++ candidate_nodes
  end

  def next_authorized_nodes(previous_tps, candidate_nodes, previous_authorized_nodes)
      when is_float(previous_tps) and previous_tps >= 1.0 and is_list(candidate_nodes) and
             is_list(previous_authorized_nodes) do
    case nb_of_authorized_nodes_to_add(previous_tps, previous_authorized_nodes) do
      0 ->
        # If the tps is not sufficient for the current distribution
        # of the node geographically, then we are not accepting new validation nodes
        previous_authorized_nodes

      nb_nodes_to_add ->
        candidate_nodes
        |> Enum.group_by(& &1.geo_patch)
        |> Enum.reduce(previous_authorized_nodes, fn {_, nodes}, acc ->
          # We are taking the nb of nodes to add by geo patch available
          acc ++ Enum.take(nodes, nb_nodes_to_add)
        end)
    end
  end

  defp nb_of_authorized_nodes_to_add(previous_tps, previous_authorized_nodes) do
    available_previous_authorized_nodes = Enum.filter(previous_authorized_nodes, & &1.available?)

    case length(previous_authorized_nodes) - length(available_previous_authorized_nodes) do
      0 ->
        # If we don't miss nodes, then we apply a distribution algorithm based
        # on the tps and geo patch
        nb_of_authorized_nodes_for_distribution(previous_tps, available_previous_authorized_nodes)

      missed_nodes ->
        # If we are missing some nodes we adding nodes to overbook the distribution
        # to ensure the security of the transactions
        missed_nodes
    end
  end

  defp nb_of_authorized_nodes_for_distribution(previous_tps, available_nodes) do
    # We are counting the number of geo patch
    # where they are available already authorized nodes
    nb_active_patches =
      available_nodes
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
    |> Crypto.derive_beacon_chain_address(date, true)
    |> storage_nodes(nodes, storage_constraints)
  end

  @doc """
  Determine if a node's public key must be a chain storage node
  """
  @spec chain_storage_node?(
          binary(),
          Transaction.transaction_type(),
          Crypto.key(),
          list(Node.t())
        ) :: boolean()
  def chain_storage_node?(
        address,
        type,
        public_key,
        node_list
      )
      when is_binary(address) and is_atom(type) and is_binary(public_key) and is_list(node_list) do
    address
    |> chain_storage_nodes_with_type(type, node_list)
    |> Utils.key_in_node_list?(public_key)
  end

  @doc """
  Determine if a node's public key must be a beacon storage node
  """
  @spec beacon_storage_node?(DateTime.t(), Crypto.key(), list(Node.t())) :: boolean()
  def beacon_storage_node?(
        timestamp = %DateTime{},
        public_key,
        node_list
      )
      when is_binary(public_key) and is_list(node_list) do
    timestamp
    |> Crypto.derive_beacon_aggregate_address()
    |> chain_storage_nodes(node_list)
    |> Utils.key_in_node_list?(public_key)
  end

  @doc """
  Determine if a node's public key must be an I/O storage node
  """
  @spec io_storage_node?(Transaction.t(), Crypto.key(), list(Node.t())) :: boolean()
  def io_storage_node?(
        %Transaction{
          validation_stamp: %ValidationStamp{
            ledger_operations: ledger_operations,
            recipients: recipients
          }
        },
        public_key,
        node_list
      )
      when is_binary(public_key) and is_list(node_list) do
    addresses = LedgerOperations.movement_addresses(ledger_operations)

    (addresses ++ recipients)
    |> io_storage_nodes(node_list)
    |> Utils.key_in_node_list?(public_key)
  end

  @doc """
  Return the storage nodes for the transaction chain based on the transaction address, the transaction type and set a nodes
  """
  @spec chain_storage_nodes_with_type(
          binary(),
          Transaction.transaction_type(),
          list(Node.t())
        ) ::
          list(Node.t())
  def chain_storage_nodes_with_type(
        address,
        type,
        node_list
      )
      when is_binary(address) and is_atom(type) and is_list(node_list) do
    if Transaction.network_type?(type) do
      node_list
    else
      chain_storage_nodes(address, node_list)
    end
  end

  @doc """
  Return the storage nodes for the transaction chain based on the transaction address and set a nodes
  """
  @spec chain_storage_nodes(binary(), list(Node.t())) :: list(Node.t())
  def chain_storage_nodes(address, node_list)
      when is_binary(address) and is_list(node_list) do
    storage_nodes(
      address,
      node_list,
      get_storage_constraints()
    )
  end

  @doc """
  Execute the hypergeometric distribution simulation
  """
  @spec hypergeometric_distribution(pos_integer()) :: pos_integer()
  defdelegate hypergeometric_distribution(nb_nodes),
    to: HypergeometricDistribution,
    as: :run_simulation
end
