defmodule UnirisCore.Mining.Worker do
  @moduledoc false

  @behaviour :gen_statem

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.P2P.Node
  alias UnirisCore.P2P
  alias UnirisCore.Election
  alias UnirisCore.Mining.BinarySequence
  alias UnirisCore.Mining.Replication
  alias UnirisCore.Mining.Stamp
  alias UnirisCore.Mining.Context
  alias UnirisCore.Mining.MaliciousDetection
  alias UnirisCore.Crypto
  alias UnirisCore.Beacon
  alias UnirisCore.TaskSupervisor
  alias UnirisCore.MiningRegistry

  # TODO: Handle the restarting of the process when failed:
  # - retrieve last state
  # - load last data
  # - use a cache or ETS to find all the information

  require Logger

  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :transient}
  end

  def start_link(opts) do
    :gen_statem.start_link(__MODULE__, opts, [])
  end

  @spec add_context(binary(), Crypto.key(), list(binary()), bitstring(), bitstring(), bitstring()) ::
          :ok
  def add_context(
        pid,
        validation_node_public_key,
        previous_storage_node_public_keys,
        cross_validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      ) do
    :gen_statem.cast(
      pid,
      {:add_context, validation_node_public_key, previous_storage_node_public_keys,
       cross_validation_nodes_view, chain_storage_nodes_view, beacon_storage_nodes_view}
    )
  end

  @spec set_replication_trees(
          pid(),
          chain_replication_tree :: list(bitstring()),
          beacon_replication_tree :: list(bitstring())
        ) :: :ok
  def set_replication_trees(pid, chain_replication_tree, beacon_replication_tree) do
    :gen_statem.cast(
      pid,
      {:set_replication_trees, chain_replication_tree, beacon_replication_tree}
    )
  end

  @spec cross_validate(pid(), ValidationStamp.t()) :: :ok
  def cross_validate(pid, stamp = %ValidationStamp{}) do
    :gen_statem.cast(pid, {:cross_validate, stamp})
  end

  @spec add_cross_validation_stamp(
          pid(),
          stamp ::
            {signature :: binary(), inconsistencies :: list(atom), public_key :: Crypto.key()}
        ) ::
          :ok
  def add_cross_validation_stamp(
        pid,
        stamp = {_sig, _inconsistencies, _public_key}
      ) do
    :gen_statem.cast(
      pid,
      {:add_cross_validation_stamp, stamp}
    )
  end

  def init(opts) do
    tx = Keyword.get(opts, :transaction)
    welcome_node_public_key = Keyword.get(opts, :welcome_node_public_key)
    validation_node_public_keys = Keyword.get(opts, :validation_node_public_keys)
    node_public_key = Keyword.get(opts, :node_public_key)

    Registry.register(MiningRegistry, tx.address, [])

    {:ok, :idle,
     %{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       node_public_key: node_public_key
     },
     [
       {:timeout, 5000, :stop_after_five_seconds},
       {:next_event, :internal, {:preliminary_verifications, validation_node_public_keys}}
     ]}
  end

  def callback_mode() do
    [:handle_event_function]
  end

  def handle_event(
        :internal,
        {:preliminary_verifications, validation_node_public_keys},
        :idle,
        data = %{transaction: tx}
      ) do
    if Transaction.valid_pending_transaction?(tx) do
      # Verify the validation nodes election performed by the welcome node
      elected_validation_nodes = Election.validation_nodes(tx)

      if Enum.map(elected_validation_nodes, & &1.last_public_key) == validation_node_public_keys do
        new_data =
          data
          |> Map.put(
            :cross_validation_nodes_view,
            BinarySequence.from_availability(cross_validation_nodes(elected_validation_nodes))
          )
          |> Map.put(:validation_nodes, elected_validation_nodes)

        {:keep_state, new_data, {:next_event, :internal, :build_context}}
      else
        Logger.error(
          "invalid welcome node election #{tx.address |> Base.encode16()}, expected: #{
            inspect(Enum.map(elected_validation_nodes, & &1.last_public_key))
          } got #{inspect(validation_node_public_keys)}"
        )

        {:stop, :normal}
      end
    else
      Logger.error("invalid pending transaction #{tx.address |> Base.encode16()}")
      {:stop, :normal}
    end
  end

  def handle_event(
        :internal,
        :build_context,
        :idle,
        data = %{
          transaction: tx,
          validation_nodes: validation_nodes,
          node_public_key: node_public_key
        }
      ) do
    chain_storage_nodes =
      if Transaction.network_type?(tx.type) do
        Enum.filter(P2P.list_nodes(), & &1.ready?)
      else
        Election.storage_nodes(tx.address)
      end

    beacon_storage_nodes =
      tx.address
      |> Beacon.subset_from_address()
      |> Beacon.get_pool(tx.timestamp)

    {previous_chain, unspent_outputs, involved_storage_nodes} = Context.fetch(tx, true)

    new_data =
      data
      |> Map.put(:chain_storage_nodes, chain_storage_nodes)
      |> Map.put(:beacon_storage_nodes, beacon_storage_nodes)
      |> Map.put(:chain_storage_nodes_view, BinarySequence.from_availability(chain_storage_nodes))
      |> Map.put(
        :beacon_storage_nodes_view,
        BinarySequence.from_availability(beacon_storage_nodes)
      )
      |> Map.put(:previous_chain, previous_chain)
      |> Map.put(:unspent_outputs, unspent_outputs)
      |> Map.put(:previous_storage_nodes, involved_storage_nodes)
      |> Map.put(:confirmed_validation_nodes, [])
      |> Map.put(:cross_validation_stamps, [])

    [%Node{last_public_key: coordinator} | _] = validation_nodes

    # Coordinator will perform additional tasks such as: aggregation of the contexts, validation stamp and replication tree creation
    if coordinator == node_public_key do
      Logger.debug("Coordinator")
      {:next_state, :coordinator, new_data}
    else
      Logger.debug("Cross validator")
      {:next_state, :cross_validator, new_data, {:next_event, :internal, :notify_context}}
    end
  end

  def handle_event(
        :internal,
        :notify_context,
        :cross_validator,
        data = %{
          transaction: tx,
          node_public_key: node_public_key,
          validation_nodes: validation_nodes,
          cross_validation_nodes_view: cross_validation_nodes_view,
          previous_storage_nodes: previous_storage_nodes,
          chain_storage_nodes_view: chain_storage_nodes_view,
          beacon_storage_nodes_view: beacon_storage_nodes_view
        }
      ) do
    Logger.debug("Send context")
    [coordinator | _] = validation_nodes

    # Send the context built to the coordinator
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      P2P.send_message(
        coordinator,
        {:add_context, tx.address, node_public_key, previous_storage_nodes,
         cross_validation_nodes_view, chain_storage_nodes_view, beacon_storage_nodes_view}
      )
    end)

    {:keep_state, data}
  end

  def handle_event(:cast, {:add_context, _, _, _, _, _}, :idle, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:add_context, from, previous_storage_nodes, cross_validation_nodes_view,
         chain_storage_nodes_view, beacon_storage_nodes_view},
        :coordinator,
        data = %{validation_nodes: validation_nodes}
      ) do
    Logger.debug("Add context")
    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    if Enum.any?(cross_validation_nodes, &(&1.last_public_key == from)) do
      # Add the previous storages nodes and aggregate the given node views with the local ones
      new_data =
        aggregate_context(
          data,
          from,
          previous_storage_nodes,
          cross_validation_nodes_view,
          chain_storage_nodes_view,
          beacon_storage_nodes_view
        )
        |> Map.update!(:confirmed_validation_nodes, &(&1 ++ [from]))

      # Wait to receive all the contexts before creation of the validation stamp
      if length(Map.get(new_data, :confirmed_validation_nodes)) == length(cross_validation_nodes) do
        {:keep_state, new_data,
         [
           {:next_event, :internal, :build_replication_trees},
           {:next_event, :internal, :create_validation_stamp}
         ]}
      else
        {:keep_state, new_data}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :internal,
        :build_replication_trees,
        :coordinator,
        data = %{
          validation_nodes: validation_nodes,
          chain_storage_nodes: chain_storage_nodes,
          beacon_storage_nodes: beacon_storage_nodes
        }
      ) do
    Logger.debug("Build replication trees")

    # TODO: use the view of storages nodes to improve the replication tree

    chain_replication_tree =
      validation_nodes
      |> Replication.tree(chain_storage_nodes)
      |> Enum.map(fn {_, list} ->
        BinarySequence.from_subset(chain_storage_nodes, list)
      end)

    beacon_replication_tree =
      validation_nodes
      |> Replication.tree(beacon_storage_nodes)
      |> Enum.map(fn {_, list} ->
        BinarySequence.from_subset(beacon_storage_nodes, list)
      end)

    # Find out the replication nodes in charge from the replication tree
    chain_replication_nodes =
      extract_nodes_from_binary_tree(chain_replication_tree, 0, chain_storage_nodes)

    beacon_replication_nodes =
      extract_nodes_from_binary_tree(beacon_replication_tree, 0, beacon_storage_nodes)

    new_data =
      data
      |> Map.put(:chain_replication_tree, chain_replication_tree)
      |> Map.put(:beacon_replication_tree, beacon_replication_tree)
      |> Map.put(:chain_replication_nodes, chain_replication_nodes)
      |> Map.put(:beacon_replication_nodes, beacon_replication_nodes)

    {:keep_state, new_data}
  end

  def handle_event(
        :internal,
        :create_validation_stamp,
        :coordinator,
        data = %{
          transaction: tx,
          previous_chain: previous_chain,
          unspent_outputs: unspent_outputs,
          welcome_node_public_key: welcome_node_public_key,
          validation_nodes: validation_nodes,
          previous_storage_nodes: previous_storage_nodes,
          chain_replication_tree: chain_replication_tree,
          beacon_replication_tree: beacon_replication_tree
        }
      ) do
    Logger.debug("Create validation stamp")
    [%Node{last_public_key: coordinator_public_key} | _] = validation_nodes
    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    # Perform Proof of Work, Proof of Integrity, Ledger operations to be
    # the stamp validating the transaction
    # This stamp will be counter validated by the cross validation nodes later
    validation_stamp =
      Stamp.create_validation_stamp(
        tx,
        previous_chain,
        unspent_outputs,
        welcome_node_public_key,
        coordinator_public_key,
        Enum.map(cross_validation_nodes, & &1.last_public_key),
        previous_storage_nodes
      )

    send_validation_stamp_and_replication_trees(
      tx.address,
      validation_stamp,
      {chain_replication_tree, beacon_replication_tree},
      cross_validation_nodes
    )

    new_data = Map.put(data, :validation_stamp, validation_stamp)
    {:next_state, :wait_cross_validation_stamps, new_data}
  end

  def handle_event(:cast, {:cross_validate, _}, :ready, _), do: {:keep_state_and_data, :postpone}

  def handle_event(:cast, {:set_replication_trees, _}, :ready, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:cross_validate, validation_stamp = %ValidationStamp{}},
        :cross_validator,
        data = %{
          transaction: tx,
          validation_nodes: validation_nodes,
          previous_chain: previous_chain,
          unspent_outputs: unspent_outputs,
          node_public_key: node_public_key
        }
      ) do
    Logger.debug("cross validate")

    cross_validation_nodes = cross_validation_nodes(validation_nodes)
    [%Node{last_public_key: coordinator_public_key} | _] = validation_nodes

    # Validate the validation stamp and
    # create the cross validation stamp by signing it or the inconsistencies found if so.
    cross_validation_stamp =
      Stamp.cross_validate(
        tx,
        validation_stamp,
        coordinator_public_key,
        Enum.map(cross_validation_nodes, & &1.last_public_key),
        previous_chain,
        unspent_outputs
      )

    # Notify the other validation nodes about the cross validation stamp previously created and signed
    # These nodes will perform their atomic commitment detection to start the replication if so
    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      Enum.reject(validation_nodes, &(&1.last_public_key == node_public_key)),
      &P2P.send_message(&1, {:cross_validation_done, tx.address, cross_validation_stamp})
    )
    |> Stream.run()

    new_data =
      data
      |> Map.put(:validation_stamp, validation_stamp)
      |> Map.put(:cross_validation_stamps, [cross_validation_stamp])

    case length(cross_validation_nodes) do
      1 ->
        # Happens when the network is bootstraping with a single authorized cross validation node
        # Do not need to check the cross validation stamp hence the atomic commitment is already reached
        # The replication can therefore be started
        {:next_state, :replication, new_data, {:next_event, :internal, :start}}

      _ ->
        {:next_state, :wait_cross_validation_stamps, new_data}
    end
  end

  def handle_event(
        :cast,
        {:set_replication_trees, chain_binary_tree, beacon_binary_tree},
        :cross_validator,
        data = %{
          validation_nodes: validation_nodes,
          chain_storage_nodes: chain_storage_nodes,
          beacon_storage_nodes: beacon_storage_nodes,
          node_public_key: node_public_key
        }
      ) do
    Logger.debug("Set replication trees")
    validator_index = Enum.find_index(validation_nodes, &(&1.last_public_key == node_public_key))

    # Find out the replication nodes in charge from the replication tree
    chain_replication_nodes =
      extract_nodes_from_binary_tree(chain_binary_tree, validator_index, chain_storage_nodes)

    beacon_replication_nodes =
      extract_nodes_from_binary_tree(beacon_binary_tree, validator_index, beacon_storage_nodes)

    {:keep_state,
     data
     |> Map.put(:chain_replication_nodes, chain_replication_nodes)
     |> Map.put(:beacon_replication_nodes, beacon_replication_nodes)}
  end

  def handle_event(:cast, {:add_cross_validation_stamp, _}, :cross_validator, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:add_cross_validation_stamp, cross_validation_stamp = {_, _, from}},
        :wait_cross_validation_stamps,
        data = %{
          validation_stamp: validation_stamp,
          validation_nodes: validation_nodes,
          cross_validation_stamps: cross_stamps
        }
      ) do
    Logger.debug("Add cross validation stamp")
    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    cond do
      !Enum.any?(cross_validation_nodes, &(&1.last_public_key == from)) ->
        :keep_state_and_data

      Stamp.valid_cross_validation_stamp?(cross_validation_stamp, validation_stamp) ->
        cross_stamps =
          [cross_validation_stamp | cross_stamps]
          |> Enum.dedup_by(fn {_, _, pub} -> pub end)

        new_data = Map.put(data, :cross_validation_stamps, cross_stamps)

        # Wait to receive all the cross validation stamp before the atomic commitment detection
        if length(cross_stamps) < length(cross_validation_nodes) do
          {:keep_state, new_data}
        else
          # Once all the cross validation stamps received, the atomic commitment is detected.
          # If so, the replication will be start
          # Otherwise, an additional work will proceed to find out the malicious nodes and bannish them
          if Stamp.atomic_commitment?(cross_stamps) do
            {:next_state, :replication, new_data, {:next_event, :internal, :start}}
          else
            {:next_state, :consenus_not_reached, new_data,
             {:next_event, :internal, :detect_malicious}}
          end
        end

      true ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :internal,
        :start,
        :replication,
        _data = %{
          transaction: tx,
          validation_stamp: validation_stamp,
          cross_validation_stamps: cross_validation_stamps,
          chain_replication_nodes: chain_replication_nodes,
          beacon_replication_nodes: beacon_replication_nodes
        }
      ) do
    Logger.debug("Replicate")

    validated_tx = %{
      tx
      | validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
    }

    Replication.run(validated_tx, chain_replication_nodes, beacon_replication_nodes)
    :keep_state_and_data
  end

  def handle_event(
        :internal,
        :detect_malicious,
        :consensus_not_reached,
        _data = %{transaction: tx}
      ) do
    Logger.error("Consensus not reached for #{Base.encode16(tx.address)}")

    MaliciousDetection.run(tx)
    :stop
  end

  def handle_event(:timeout, :stop_after_five_seconds, _state, _data) do
    :stop
  end

  def handle_event(_, msg, state, _data = %{transaction: %Transaction{address: tx_address}}) do
    Logger.debug(
      "Unexpected message: #{inspect(msg)} in state #{inspect(state)} for #{
        Base.encode16(tx_address)
      }"
    )

    :keep_state_and_data
  end

  def terminate(:normal, _, _), do: :ok

  def terminate(reason, _, _) do
    Logger.error("#{inspect(reason)}")
  end

  defp aggregate_context(
         state,
         from,
         previous_storage_nodes,
         cross_validation_nodes_view,
         chain_storage_nodes_view,
         beacon_storage_nodes_view
       ) do
    state
    |> Map.update(:confirm_validation_nodes, [from], &(&1 ++ [from]))
    |> Map.update!(
      :cross_validation_nodes_view,
      &BinarySequence.aggregate(&1, cross_validation_nodes_view)
    )
    |> Map.update!(
      :chain_storage_nodes_view,
      &BinarySequence.aggregate(&1, chain_storage_nodes_view)
    )
    |> Map.update!(
      :beacon_storage_nodes_view,
      &BinarySequence.aggregate(&1, beacon_storage_nodes_view)
    )
    |> Map.update(
      :previous_storage_nodes,
      previous_storage_nodes,
      &(&1 ++ previous_storage_nodes)
    )
  end

  defp send_validation_stamp_and_replication_trees(
         tx_address,
         stamp = %ValidationStamp{},
         {chain_replication_tree, beacon_replication_tree},
         cross_validation_nodes
       ) do
    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      cross_validation_nodes,
      &P2P.send_message(&1, [
        {:set_replication_trees, tx_address, chain_replication_tree, beacon_replication_tree},
        {:cross_validate, tx_address, stamp}
      ])
    )
    |> Stream.run()
  end

  defp cross_validation_nodes([_ | cross_validation_nodes])
       when length(cross_validation_nodes) > 0 do
    cross_validation_nodes
  end

  defp cross_validation_nodes(validation_nodes), do: validation_nodes

  defp extract_nodes_from_binary_tree(binary_tree, validator_index, storage_nodes) do
    %{list: nodes} =
      binary_tree
      |> Enum.at(validator_index)
      |> BinarySequence.extract()
      |> Enum.reduce(%{index: 0, list: []}, fn included, acc ->
        case included do
          0 ->
            Map.update!(acc, :index, &(&1 + 1))

          1 ->
            acc
            |> Map.update!(:list, &(&1 ++ [Enum.at(storage_nodes, acc.index)]))
            |> Map.update!(:index, &(&1 + 1))
        end
      end)

    nodes
  end
end
