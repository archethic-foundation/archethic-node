defmodule UnirisCore.Mining.Worker do
  @moduledoc false

  @behaviour :gen_statem

  alias UnirisCore.Transaction
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerOperations
  alias UnirisCore.Transaction.CrossValidationStamp
  alias UnirisCore.P2P.Node
  alias UnirisCore.P2P
  alias UnirisCore.Election
  alias UnirisCore.Mining.BinarySequence
  alias UnirisCore.Mining.Replication
  alias UnirisCore.Mining.Context
  alias UnirisCore.Mining.MaliciousDetection
  alias UnirisCore.Crypto
  alias UnirisCore.TaskSupervisor
  alias UnirisCore.MiningRegistry
  alias UnirisCore.Beacon
  alias UnirisCore.P2P.Message.AddContext
  alias UnirisCore.P2P.Message.CrossValidate
  alias UnirisCore.P2P.Message.CrossValidationDone
  alias UnirisCore.P2P.Message.ReplicateTransaction

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

  @spec add_context(address :: binary(), validation_node :: Crypto.key(), context :: Context.t()) ::
          :ok
  def add_context(pid, validation_node_public_key, context = %Context{})
      when is_pid(pid) and is_binary(validation_node_public_key) do
    :gen_statem.cast(
      pid,
      {:add_context, validation_node_public_key, context}
    )
  end

  @spec cross_validate(pid(), ValidationStamp.t(), replication_tree :: list(bitstring())) :: :ok
  def cross_validate(pid, stamp = %ValidationStamp{}, replication_tree) do
    :gen_statem.cast(pid, {:cross_validate, stamp, replication_tree})
  end

  @spec add_cross_validation_stamp(pid(), stamp :: CrossValidationStamp.t()) :: :ok
  def add_cross_validation_stamp(pid, stamp = %CrossValidationStamp{}) do
    :gen_statem.cast(pid, {:add_cross_validation_stamp, stamp})
  end

  def init(opts) do
    tx = Keyword.get(opts, :transaction)
    welcome_node_public_key = Keyword.get(opts, :welcome_node_public_key)
    validation_node_public_keys = Keyword.get(opts, :validation_node_public_keys)
    node_public_key = Keyword.get(opts, :node_public_key)

    Registry.register(MiningRegistry, tx.address, [])

    Logger.info("New transaction mining for #{Base.encode16(tx.address)}")

    {:ok, :idle,
     %{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       node_public_key: node_public_key
     },
     [
       {{:timeout, :stop_after_five_seconds}, 3000, :any},
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
        {:keep_state, Map.put(data, :validation_nodes, elected_validation_nodes),
         {:next_event, :internal, :build_context}}
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

    context =
      %Context{}
      |> Context.compute_p2p_view(
        cross_validation_nodes(validation_nodes),
        chain_storage_nodes,
        beacon_storage_nodes
      )
      |> Context.fetch_history(tx)

    Logger.info("Context initialized for #{Base.encode16(tx.address)}")

    new_data =
      data
      |> Map.put(:context, context)
      |> Map.put(:confirmed_validation_nodes, [])
      |> Map.put(:cross_validation_stamps, [])
      |> Map.put(:chain_storage_nodes, chain_storage_nodes)
      |> Map.put(:beacon_storage_nodes, beacon_storage_nodes)

    [%Node{last_public_key: coordinator} | _] = validation_nodes

    # Coordinator will perform additional tasks such as: aggregation of the contexts, validation stamp and replication tree creation
    if coordinator == node_public_key do
      Logger.info("Start validation as coordinator for #{Base.encode16(tx.address)}")
      {:next_state, :coordinator, new_data}
    else
      Logger.info("Start validation as cross validator for #{Base.encode16(tx.address)}")
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
          context: context
        }
      ) do
    Logger.info("Send context for #{Base.encode16(tx.address)}")

    [coordinator | _] = validation_nodes

    # Send the context built to the coordinator
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      P2P.send_message(
        coordinator,
        %AddContext{
          address: tx.address,
          validation_node_public_key: node_public_key,
          context: context
        }
      )
    end)

    {:keep_state, data}
  end

  def handle_event(:cast, {:add_context, _, _, _, _, _}, :idle, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:add_context, from, new_context = %Context{}},
        :coordinator,
        data = %{transaction: tx, validation_nodes: validation_nodes}
      ) do
    Logger.info("Add context for #{Base.encode16(tx.address)}")
    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    if Enum.any?(cross_validation_nodes, &(&1.last_public_key == from)) do
      # Aggregate context and flag the cross validation node sending the
      # request as confirmed
      new_data =
        data
        |> Map.update(:confirmed_validation_nodes, [from], &[from | &1])
        |> Map.update!(:context, &Context.aggregate(&1, new_context))

      # Wait to receive all the contexts before creation of the validation stamp
      if length(Map.get(new_data, :confirmed_validation_nodes)) == length(cross_validation_nodes) do
        {:keep_state, new_data,
         [
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
        :create_validation_stamp,
        :coordinator,
        data = %{
          transaction: tx,
          context: context,
          welcome_node_public_key: welcome_node_public_key,
          validation_nodes: validation_nodes,
          chain_storage_nodes: chain_storage_nodes,
          beacon_storage_nodes: beacon_storage_nodes
        }
      ) do
    Logger.info("Create validation stamp of #{Base.encode16(tx.address)}")
    [%Node{last_public_key: coordinator_public_key} | _] = validation_nodes
    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    # Perform Proof of Work, Proof of Integrity, Ledger operations to be
    # the stamp validating the transaction
    # This stamp will be counter validated by the cross validation nodes later
    validation_stamp =
      %ValidationStamp{ledger_operations: ledger_ops} =
      ValidationStamp.new(
        tx,
        context,
        welcome_node_public_key,
        coordinator_public_key,
        Enum.map(cross_validation_nodes, & &1.last_public_key)
      )

    # Build the replication using the storage nodes including
    # - Chain storage nodes
    # - Beacon storage nodes
    # - IO storage nodes (node rewards, outputs)
    storage_nodes =
      chain_storage_nodes ++ beacon_storage_nodes ++ LedgerOperations.io_storage_nodes(ledger_ops)

    replication_tree = create_replication_tree(validation_nodes, storage_nodes)

    send_validation_stamp_and_replication_trees(
      tx.address,
      validation_stamp,
      replication_tree,
      cross_validation_nodes
    )

    # Find out the replication nodes in charge from the replication tree
    replication_nodes = extract_nodes_from_binary_tree(replication_tree, 0, storage_nodes)

    new_data =
      data
      |> Map.put(:validation_stamp, validation_stamp)
      |> Map.put(:replication_tree, replication_tree)
      |> Map.put(:replication_nodes, replication_nodes)

    {:next_state, :wait_cross_validation_stamps, new_data}
  end

  def handle_event(:cast, {:cross_validate, _}, :ready, _), do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:cross_validate,
         validation_stamp = %ValidationStamp{
           ledger_operations: ledger_ops
         }, replication_tree},
        :cross_validator,
        data = %{
          transaction: tx,
          validation_nodes: validation_nodes,
          context: context,
          node_public_key: node_public_key,
          chain_storage_nodes: chain_storage_nodes,
          beacon_storage_nodes: beacon_storage_nodes
        }
      ) do
    Logger.info("Cross validation of #{Base.encode16(tx.address)}")

    cross_validation_nodes = cross_validation_nodes(validation_nodes)
    [%Node{last_public_key: coordinator_public_key} | _] = validation_nodes

    inconsistencies =
      validation_stamp
      |> ValidationStamp.inconsistencies(
        tx,
        coordinator_public_key,
        Enum.map(cross_validation_nodes, & &1.last_public_key),
        context
      )

    # Verify the replication tree
    storage_nodes =
      chain_storage_nodes ++ beacon_storage_nodes ++ LedgerOperations.io_storage_nodes(ledger_ops)

    unless replication_tree == create_replication_tree(validation_nodes, storage_nodes) do
      # TODO: define a recovery strategy
      raise "Invalid replication tree"
    end

    validator_index = Enum.find_index(validation_nodes, &(&1.last_public_key == node_public_key))

    replication_nodes =
      extract_nodes_from_binary_tree(replication_tree, validator_index, storage_nodes)

    cross_validation_stamp = CrossValidationStamp.new(validation_stamp, inconsistencies)

    # Notify the other validation nodes about the cross validation stamp previously created and signed
    # These nodes will perform their atomic commitment detection to start the replication if so
    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      Enum.reject(validation_nodes, &(&1.last_public_key == node_public_key)),
      &P2P.send_message(&1, %CrossValidationDone{
        address: tx.address,
        cross_validation_stamp: cross_validation_stamp
      })
    )
    |> Stream.run()

    new_data =
      data
      |> Map.put(:validation_stamp, validation_stamp)
      |> Map.put(:cross_validation_stamps, [cross_validation_stamp])
      |> Map.put(:replication_nodes, replication_nodes)
      |> Map.put(:replication_tree, replication_tree)

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

  def handle_event(:cast, {:add_cross_validation_stamp, _}, :cross_validator, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:add_cross_validation_stamp,
         cross_validation_stamp = %CrossValidationStamp{node_public_key: from}},
        :wait_cross_validation_stamps,
        data = %{
          transaction: tx,
          validation_stamp: validation_stamp,
          validation_nodes: validation_nodes,
          cross_validation_stamps: cross_stamps
        }
      ) do
    Logger.info("Add cross validation stamp for #{Base.encode16(tx.address)}")
    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    cond do
      !Enum.any?(cross_validation_nodes, &(&1.last_public_key == from)) ->
        :keep_state_and_data

      CrossValidationStamp.valid?(cross_validation_stamp, validation_stamp) ->
        cross_stamps =
          [cross_validation_stamp | cross_stamps]
          |> Enum.dedup_by(& &1.node_public_key)

        new_data = Map.put(data, :cross_validation_stamps, cross_stamps)

        # Wait to receive all the cross validation stamp before the atomic commitment detection
        if length(cross_stamps) < length(cross_validation_nodes) do
          {:keep_state, new_data}
        else
          # Once all the cross validation stamps received, the atomic commitment is detected.
          # If so, the replication will be start
          # Otherwise, an additional work will proceed to find out the malicious nodes and bannish them
          if Transaction.atomic_commitment?(%{
               tx
               | validation_stamp: validation_stamp,
                 cross_validation_stamps: cross_stamps
             }) do
            {:next_state, :replication, new_data, {:next_event, :internal, :start}}
          else
            {:next_state, :consensus_not_reached, new_data,
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
          replication_nodes: replication_nodes
        }
      ) do
    Logger.info("Start replication for #{Base.encode16(tx.address)}")

    validated_tx = %{
      tx
      | validation_stamp: validation_stamp,
        cross_validation_stamps: cross_validation_stamps
    }

    # Starts the process of replication for the replication nodes depending on the validation node position in the tree
    # Once the transaction is received, the nodes will performed either chain validation or transaction only validation
    # depending on their storage role (chain storage nodes, beacon storage node, outputs node, involved node for the mining)
    Task.Supervisor.async_stream_nolink(TaskSupervisor, replication_nodes, fn node ->
      P2P.send_message(node, %ReplicateTransaction{transaction: validated_tx})
    end)
    |> Stream.run()

    :stop
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

  def handle_event({:timeout, :stop_after_five_seconds}, :any, _state, _data) do
    :stop
  end

  def handle_event(_, msg, state, data = %{transaction: %Transaction{address: tx_address}}) do
    Logger.debug(
      "Unexpected message: #{inspect(msg)} in state #{inspect(state)} in #{inspect(data)} for #{
        Base.encode16(tx_address)
      }"
    )

    :stop
  end

  def terminate(:normal, _, _), do: :ok

  def terminate(reason, _, _) do
    Logger.error("#{inspect(reason)}")
  end

  defp send_validation_stamp_and_replication_trees(
         tx_address,
         stamp = %ValidationStamp{},
         replication_tree,
         cross_validation_nodes
       ) do
    TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      cross_validation_nodes,
      &P2P.send_message(&1, %CrossValidate{
        address: tx_address,
        validation_stamp: stamp,
        replication_tree: replication_tree
      })
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

  defp create_replication_tree(validation_nodes, storage_nodes) do
    storage_nodes =
      storage_nodes
      |> :lists.flatten()
      |> Enum.uniq()

    validation_nodes
    |> Replication.tree(storage_nodes)
    |> Enum.map(fn {_, list} ->
      BinarySequence.from_subset(storage_nodes, list)
    end)
  end
end
