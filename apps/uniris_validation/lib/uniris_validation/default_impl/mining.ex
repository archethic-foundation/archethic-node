defmodule UnirisValidation.DefaultImpl.Mining do
  @moduledoc false

  alias UnirisValidation.DefaultImpl.Replication
  alias UnirisValidation.DefaultImpl.BinarySequence
  alias UnirisValidation.DefaultImpl.Stamp
  alias UnirisValidation.DefaultImpl.ProofOfWork
  alias UnirisValidation.DefaultImpl.ContextBuilding
  alias UnirisValidation.TaskSupervisor
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisElection, as: Election
  alias UnirisP2P, as: P2P
  alias UnirisP2P.Node
  alias UnirisCrypto, as: Crypto

  require Logger

  @behaviour :gen_statem

  def child_spec(arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}}
  end

  def start_link(opts \\ []) do
    %Transaction{address: tx_address} = Keyword.get(opts, :transaction)
    :gen_statem.start_link(via_tuple(tx_address), __MODULE__, opts, [])
  end

  def init(opts) do
    tx = Keyword.get(opts, :transaction)
    welcome_node_public_key = Keyword.get(opts, :welcome_node_public_key)
    validation_node_public_keys = Keyword.get(opts, :validation_node_public_keys)

    data = %{
      transaction: tx,
      welcome_node_public_key: welcome_node_public_key,
      validation_node_public_keys: validation_node_public_keys,
      node_public_key: Crypto.node_public_key()
    }

    Logger.info("Mining starting for #{tx.address |> Base.encode16()}")

    {:ok, :started, data, {:next_event, :internal, {:precheck, validation_node_public_keys}}}
  end

  def callback_mode do
    [:handle_event_function]
  end

  def handle_event(
        :internal,
        {:precheck, validation_node_public_keys},
        :started,
        data = %{transaction: tx}
      ) do
    if Transaction.valid_pending_transaction?(tx) do
      # Verify welcome node validaiton node election
      elected_validation_nodes = Election.validation_nodes(tx)

      if Enum.map(elected_validation_nodes, & &1.last_public_key) == validation_node_public_keys do
        new_data =
          data
          |> Map.put(:validation_nodes, elected_validation_nodes)
          |> Map.put(
            :validation_nodes_view,
            BinarySequence.from_availability(cross_validation_nodes(elected_validation_nodes))
          )

        {:keep_state, new_data, {:next_event, :internal, :start_mining}}
      else
        Logger.error("invalid welcome node election #{tx.address |> Base.encode16()}")

        {:next_state, :invalid_welcome_node_election, data}
      end
    else
      Logger.error("invalid pending transaction #{tx.address |> Base.encode16()}")
      {:next_state, :invalid_pending_transaction, data}
    end
  end

  def handle_event(
        :internal,
        :start_mining,
        :started,
        data = %{
          transaction: tx,
          node_public_key: node_public_key,
          validation_nodes:
            validation_nodes = [%Node{last_public_key: coordinator_public_key} | _]
        }
      ) do
    # Compute the storage node and the P2P view in a binary format
    storage_nodes = storage_nodes(tx)

    new_data =
      data
      |> Map.put(:storage_nodes, storage_nodes)
      |> Map.put(:storage_nodes_view, BinarySequence.from_availability(storage_nodes))

    # Run the context building phase
    context_building_task =
      Task.Supervisor.async(TaskSupervisor, ContextBuilding, :with_confirmation, [tx])

    new_data = Map.put(new_data, :context_building_task, context_building_task)

    if node_public_key == coordinator_public_key do
      if length(validation_nodes) == 1 do
        {:next_state, :coordinator_and_cross_validator, new_data}
      else
        Logger.debug("Coordinator")
        {:next_state, :coordinator, new_data}
      end
    else
      Logger.debug("Cross validator")
      {:next_state, :cross_validator, new_data}
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, _, _, _reason},
        _,
        _data = %{
          transaction: %Transaction{address: tx_address},
          context_building_task: %Task{ref: t_ref}
        }
      )
      when ref == t_ref do
    Logger.info("End of context building for #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {ref, {:ok, chain, unspent_outputs, nodes}},
        state,
        data = %{
          transaction: %Transaction{address: tx_address},
          context_building_task: %Task{ref: t_ref},
          validation_nodes: [coordinator | _],
          storage_nodes_view: storage_nodes_view,
          validation_nodes_view: validation_nodes_view,
          node_public_key: node_public_key
        }
      )
      when state in [:cross_validator, :coordinator_and_cross_validator] and ref == t_ref do
    # Notify the coordinator about the context building + P2P view about
    # the cross validation nodes and next storage nodes
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      P2P.send_message(
        coordinator,
        {:add_context, tx_address, node_public_key, nodes, validation_nodes_view,
         storage_nodes_view}
      )
    end)

    {:keep_state, update_data_from_context(data, chain, unspent_outputs, nodes)}
  end

  def handle_event(
        :info,
        {ref, {:ok, chain, unspent_outputs, nodes}},
        _,
        data = %{
          context_building_task: %Task{ref: t_ref}
        }
      )
      when ref == t_ref do
    {:keep_state, update_data_from_context(data, chain, unspent_outputs, nodes)}
  end

  def handle_event(
        :cast,
        {:cross_validate, stamp = %ValidationStamp{}},
        state,
        data = %{
          transaction: tx = %Transaction{address: tx_address},
          previous_chain: previous_chain,
          unspent_outputs: unspent_outputs,
          validation_nodes:
            validation_nodes = [
              %Node{last_public_key: coordinator_public_key} | _
            ],
          node_public_key: node_public_key
        }
      )
      when state in [
             :cross_validator,
             :coordinator_and_cross_validator,
             :waiting_cross_validation_stamps
           ] do
    Logger.info("Start cross validation for #{tx_address |> Base.encode16()}")

    cross_validation_stamp =
      case Stamp.check_validation_stamp(
             tx,
             stamp,
             coordinator_public_key,
             cross_validation_nodes(validation_nodes) |> Enum.map(& &1.last_public_key),
             previous_chain,
             unspent_outputs
           ) do
        :ok ->
          Stamp.create_cross_validation_stamp(stamp, [], node_public_key)

        {:error, inconsistencies} ->
          Stamp.create_cross_validation_stamp(stamp, inconsistencies, node_public_key)
      end

    Enum.each(validation_nodes, fn n ->
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        P2P.send_message(n, {:cross_validation_done, tx.address, cross_validation_stamp})
      end)
    end)

    new_data =
      data
      |> Map.put(:cross_validation_stamps, [cross_validation_stamp])
      |> Map.put(:validation_stamp, stamp)

    Logger.info("End cross validation for #{tx_address |> Base.encode16()}")
    {:next_state, :waiting_cross_validation_stamps, new_data}
  end

  def handle_event(
        :cast,
        {:set_replication_tree, binary_tree},
        _,
        data = %{
          validation_nodes: validation_nodes,
          storage_nodes: storage_nodes,
          node_public_key: node_public_key
        }
      ) do
    validator_index = Enum.find_index(validation_nodes, &(&1.last_public_key == node_public_key))

    %{list: replication_nodes} =
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

    {:keep_state, Map.put(data, :replication_nodes, replication_nodes)}
  end

  def handle_event(
        :cast,
        {:add_context, from, previous_storage_nodes, validation_nodes_view, storage_nodes_view},
        state,
        data = %{
          validation_nodes: validation_nodes
        }
      )
      when state in [:coordinator, :coordinator_and_cross_validator] do
    new_data =
      data
      |> Map.update(:confirm_validation_nodes, [from], &(&1 ++ [from]))
      |> Map.update!(:validation_nodes_view, &BinarySequence.aggregate(&1, validation_nodes_view))
      |> Map.update!(:storage_nodes_view, &BinarySequence.aggregate(&1, storage_nodes_view))
      |> Map.update(
        :previous_storage_nodes,
        previous_storage_nodes,
        &(&1 ++ previous_storage_nodes)
      )

    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    new_data.confirm_validation_nodes
    |> length()
    |> case do
      # Wait to receive all the context building before to create stamp and waiting cross validations
      len when len == length(cross_validation_nodes) ->
        {:keep_state, new_data, {:next_event, :internal, :create_validation_stamp}}

      _ ->
        {:keep_state, new_data}
    end
  end

  def handle_event(
        :internal,
        :create_validation_stamp,
        state,
        data = %{
          transaction: tx = %Transaction{address: tx_address},
          unspent_outputs: unspent_outputs,
          previous_chain: previous_chain,
          previous_storage_nodes: previous_storage_nodes,
          storage_nodes: storage_nodes,
          welcome_node_public_key: welcome_node_public_key,
          validation_nodes:
            validation_nodes = [
              %Node{last_public_key: coordinator_public_key} | _
            ]
        }
      )
      when state in [:coordinator, :coordinator_and_cross_validator] do
    Logger.info("Start validation stamp creation for #{tx_address |> Base.encode16()}")

    pow_result = ProofOfWork.run(tx)

    cross_validation_nodes = cross_validation_nodes(validation_nodes)

    stamp =
      Stamp.create_validation_stamp(
        tx,
        previous_chain,
        unspent_outputs,
        welcome_node_public_key,
        coordinator_public_key,
        cross_validation_nodes |> Enum.map(& &1.last_public_key),
        previous_storage_nodes,
        pow_result
      )

    replication_tree = Replication.build_binary_tree(validation_nodes, storage_nodes)

    # Send cross validation request and replication tree computation to the available
    # cross validation nodes
    Enum.each(cross_validation_nodes, fn n ->
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        P2P.send_message(n, [
          {:set_replication_tree, tx.address, replication_tree},
          {:cross_validate, tx.address, stamp}
        ])
      end)
    end)

    Logger.info("End validation stamp creation for #{tx_address |> Base.encode16()}")

    {:next_state, :waiting_cross_validation_stamps,
     data |> Map.put(:stamp, stamp) |> Map.put(:replication_tree, replication_tree)}
  end

  def handle_event(
        :cast,
        {:add_cross_validation_stamp, cross_validation_stamp},
        :waiting_cross_validation_stamps,
        data = %{
          validation_stamp: stamp,
          validation_nodes: validation_nodes,
          cross_validation_stamps: cross_stamps
        }
      ) do
    if Stamp.valid_cross_validation_stamp?(cross_validation_stamp, stamp) do
      cross_stamps =
        [cross_validation_stamp | cross_stamps]
        |> Enum.dedup_by(fn {_, _, pub} -> pub end)

      new_data = Map.put(data, :cross_validation_stamps, cross_stamps)

      # Wait to receive the all the cross validation stamps and to reach
      # the atomic commitment before to start replication
      if length(cross_stamps) < length(cross_validation_nodes(validation_nodes)) do
        {:keep_state, new_data}
      else
        Enum.dedup_by(cross_stamps, fn {_, inconsistencies, _} -> inconsistencies end)
        |> length
        |> case do
          1 ->
            {:next_state, :replication, new_data, {:next_event, :internal, :send_transaction}}

          _ ->
            {:next_state, :atomic_commitment_not_reach, new_data,
             {:next_event, :internal, :init_malicious_detection}}
        end
      end
    else
      Logger.error("invalid cross validation stamp #{inspect cross_validation_stamp}")
      :keep_state_and_data
    end
  end

  def handle_event(
        :internal,
        :init_malicious_detection,
        :atomic_commitment_not_reach,
        _data = %{transaction: %Transaction{address: tx_address}}
      ) do
    Logger.error("Atomic commitment not reach for #{tx_address |> Base.encode16()}")

    # TODO: Malicious detection
    :keep_state_and_data
  end

  def handle_event(:internal, :send_transaction, :replication, %{
        transaction: tx,
        validation_stamp: stamp,
        cross_validation_stamps: cross_validation_stamps,
        replication_nodes: replication_nodes
      }) do
    Logger.info("Start replication")

    validated_transaction =
      tx
      |> Map.put(:validation_stamp, stamp)
      |> Map.put(:cross_validation_stamps, cross_validation_stamps)

    Enum.each(replication_nodes, fn n ->
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        P2P.send_message(n, {:replicate_transaction, validated_transaction})
      end)
    end)

    :keep_state_and_data
  end

  def handle_event({:call, from}, :transaction, _, %{transaction: tx}) do
    {:keep_state_and_data, {:reply, from, tx}}
  end

  def handle_event(_event, msg, state, _data) do
    Logger.debug("Unexpected message: state: #{state} - message: #{inspect(msg)}")
    :keep_state_and_data
  end

  @spec add_cross_validation_stamp(
          binary(),
          stamp ::
            {signature :: binary(), inconsistencies :: list(atom), public_key :: Crypto.key()}
        ) ::
          :ok
  def add_cross_validation_stamp(
        tx_address,
        stamp = {_sig, _inconsistencies, _public_key}
      ) do
    :gen_statem.cast(
      via_tuple(tx_address),
      {:add_cross_validation_stamp, stamp}
    )
  end

  @spec set_replication_tree(binary(), list(bitstring())) :: :ok
  def set_replication_tree(tx_address, tree) do
    :gen_statem.cast(via_tuple(tx_address), {:set_replication_tree, tree})
  end

  @spec add_context(binary(), Crypto.key(), list(binary()), bitstring(), bitstring()) :: :ok
  def add_context(
        tx_address,
        validation_node_public_key,
        previous_storage_node_public_keys,
        validation_nodes_view,
        storage_nodes_view
      ) do
    :gen_statem.cast(
      via_tuple(tx_address),
      {:add_context, validation_node_public_key, previous_storage_node_public_keys,
       validation_nodes_view, storage_nodes_view}
    )
  end

  @spec cross_validate(binary(), ValidationStamp.t()) :: :ok
  def cross_validate(tx_address, stamp = %ValidationStamp{}) do
    :gen_statem.cast(via_tuple(tx_address), {:cross_validate, stamp})
  end

  defp via_tuple(tx_address) do
    {:via, Registry, {UnirisValidation.MiningRegistry, tx_address}}
  end

  defp update_data_from_context(data, previous_chain, unspent_outputs, nodes) do
    data
    |> Map.put(:previous_chain, previous_chain)
    |> Map.put(:unspent_outputs, unspent_outputs)
    |> Map.put(:previous_storage_nodes, nodes)
  end

  defp storage_nodes(%Transaction{address: tx_address, type: type}) do
    if type in [:node, :code] do
      P2P.list_nodes()
    else
      Election.storage_nodes(tx_address)
    end
  end

  defp cross_validation_nodes(validation_nodes = [_]) do
    validation_nodes
  end

  defp cross_validation_nodes([_ | cross_validation_nodes]) do
    cross_validation_nodes
  end
end
