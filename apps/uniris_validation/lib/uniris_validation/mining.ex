defmodule UnirisValidation.Mining do
  @moduledoc false

  alias UnirisValidation.Replication
  alias UnirisValidation.BinarySequence
  alias UnirisValidation.Stamp
  alias UnirisValidation.ProofOfWork
  alias UnirisValidation.ContextBuilding
  alias UnirisValidation.TaskSupervisor
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisElection, as: Election
  alias UnirisNetwork, as: Network
  alias UnirisNetwork.Node
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
      validation_node_public_keys: validation_node_public_keys
    }

    {:ok, :started, data, {:next_event, :internal, {:precheck, validation_node_public_keys}}}
  end

  def callback_mode do
    [:state_functions, :state_enter]
  end

  def started(:enter, _, _data = %{transaction: tx}) do
    Logger.info("Mining starting for #{tx.address |> Base.encode16()}")
    :keep_state_and_data
  end

  def started(
        :internal,
        {:precheck, validation_node_public_keys},
        data = %{transaction: tx}
      ) do
    if Transaction.valid_pending_transaction?(tx) do
      # Verify welcome node validaiton node election
      elected_validation_nodes =
        [_ | cross_validation_nodes] =
        Election.validation_nodes(tx, Network.list_nodes(), Network.daily_nonce())

      if Enum.map(elected_validation_nodes, & &1.last_public_key) == validation_node_public_keys do
        new_data =
          data
          |> Map.put(:validation_nodes, elected_validation_nodes)
          |> Map.put(
            :validation_nodes_view,
            BinarySequence.from_availability(cross_validation_nodes)
          )

        {:keep_state, new_data, {:next_event, :internal, :start_mining}}
      else
        {:next_state, :invalid_welcome_node_election, data}
      end
    else
      {:next_state, :invalid_pending_transaction, data}
    end
  end

  def started(
        :internal,
        :start_mining,
        data = %{
          transaction: tx,
          validation_nodes: [%Node{last_public_key: coordinator_public_key} | _]
        }
      ) do
    # Compute the storage node and the P2P view in a binary format
    storage_nodes =
      Election.storage_nodes(tx.address, Network.list_nodes(), Network.storage_nonce())

    storage_nodes_view = BinarySequence.from_availability(storage_nodes)

    new_data =
      data
      |> Map.put(:storage_nodes, storage_nodes)
      |> Map.put(:storage_nodes_view, storage_nodes_view)

    # Run the context building phase
    context_building_task =
      Task.Supervisor.async(TaskSupervisor, ContextBuilding, :with_confirmation, [tx])

    new_data = Map.put(new_data, :context_building_task, context_building_task)

    # Execute the Proof of work if coordinator
    if Crypto.last_node_public_key() == coordinator_public_key do
      pow_task = Task.Supervisor.async(TaskSupervisor, ProofOfWork, :run, [tx])
      {:next_state, :coordinator, Map.put(new_data, :pow_task, pow_task)}
    else
      {:next_state, :cross_validator, new_data}
    end
  end

  def invalid_pending_transaction(
        :enter,
        _,
        _data = %{transaction: %Transaction{address: tx_address}}
      ) do
    Logger.error("invalid pending transaction #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def invalid_welcome_node_election(
        :enter,
        _,
        _data = %{transaction: %Transaction{address: tx_address}}
      ) do
    Logger.error("invalid welcome node election #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def cross_validator(:enter, _, _data = %{transaction: %Transaction{address: tx_address}}) do
    Logger.info("Cross validation work started for #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def cross_validator(
        :info,
        {:DOWN, ref, _, _, _reason},
        _data = %{
          transaction: %Transaction{address: tx_address},
          context_building_task: %Task{ref: t_ref}
        }
      )
      when ref == t_ref do
    Logger.info("End of context building for #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def cross_validator(
        :info,
        {ref, result},
        data = %{
          transaction: %Transaction{address: tx_address},
          context_building_task: %Task{ref: t_ref},
          validation_nodes: [coordinator | _],
          storage_nodes_view: storage_nodes_view,
          validation_nodes_view: validation_nodes_view
        }
      )
      when ref == t_ref do
    case result do
      {:ok, chain, unspent_outputs, nodes} ->
        new_data =
          data
          |> Map.put(:previous_chain, chain)
          |> Map.put(:unspent_outputs, unspent_outputs)
          |> Map.put(:previous_storage_nodes, nodes)

        # Notify the coordinator about the context building + P2P view about
        # the cross validation nodes and next storage nodes
        Task.Supervisor.start_child(TaskSupervisor, fn ->
          Network.send_message(
            coordinator,
            {:add_context, tx_address, nodes, validation_nodes_view, storage_nodes_view}
          )
        end)

        {:keep_state, new_data}
    end
  end

  def cross_validator(
        :cast,
        {:cross_validate, stamp = %ValidationStamp{}},
        data = %{
          transaction: tx = %Transaction{address: tx_address},
          previous_chain: previous_chain,
          unspent_outputs: unspent_outputs,
          validation_nodes:
            validation_nodes = [
              %Node{last_public_key: coordinator_public_key} | cross_validation_nodes
            ]
        }
      ) do
    Logger.info("Start cross validation for #{tx_address |> Base.encode16()}")

    cross_validation_stamp =
      case Stamp.check_validation_stamp(
             tx,
             stamp,
             coordinator_public_key,
             cross_validation_nodes |> Enum.map(& &1.last_public_key),
             previous_chain,
             unspent_outputs
           ) do
        :ok ->
          Stamp.create_cross_validation_stamp(stamp, [])

        {:error, inconsistencies} ->
          Stamp.create_cross_validation_stamp(stamp, inconsistencies)
      end

    Task.Supervisor.async_stream(TaskSupervisor, validation_nodes, fn n ->
      Network.send_message(n, {:cross_validation_done, tx.address, cross_validation_stamp})
    end)
    |> Stream.run()

    new_data =
      data
      |> Map.put(:cross_validation_stamps, [
        {Crypto.last_node_public_key(), cross_validation_stamp}
      ])
      |> Map.put(:validation_stamp, stamp)

    {:next_state, :waiting_cross_validation_stamps, new_data}
  end

  def cross_validator(
        :cast,
        {:set_replication_tree, binary_tree},
        data = %{
          validation_nodes: validation_nodes,
          storage_nodes: storage_nodes
        }
      ) do
    pub = Crypto.last_node_public_key()
    validator_index = Enum.find_index(validation_nodes, &(&1.last_public_key == pub))

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

  def coordinator(:enter, _, _data = %{transaction: %Transaction{address: tx_address}}) do
    Logger.info("Coordinator work started for #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def coordinator(
        :info,
        {:DOWN, ref, _, _, _reason},
        _data = %{
          transaction: tx,
          context_building_task: %Task{ref: context_ref},
          pow_task: %Task{ref: pow_ref}
        }
      ) do
    case ref do
      ref when ref == context_ref ->
        Logger.info("End of context building for #{tx.address |> Base.encode16()}")

      ref when ref == pow_ref ->
        Logger.info("End of proof of work for #{tx.address |> Base.encode16()}")
    end

    :keep_state_and_data
  end

  def coordinator(:info, {ref, result}, data = %{context_building_task: %Task{ref: t_ref}})
      when ref == t_ref do
    case result do
      {:ok, chain, unspent_outputs, nodes} ->
        new_data =
          data
          |> Map.put(:previous_chain, chain)
          |> Map.put(:unspent_outputs, unspent_outputs)
          |> Map.put(:previous_storage_nodes, nodes)

        {:keep_state, new_data}
    end
  end

  def coordinator(:info, {ref, result}, data = %{pow_task: %Task{ref: t_ref}})
      when t_ref == ref do
    {:keep_state, Map.put(data, :proof_of_work, result)}
  end

  def coordinator(
        :cast,
        {:add_context, from, previous_storage_nodes, validation_nodes_view, storage_nodes_view},
        data = %{
          validation_nodes: [_ | cross_validation_nodes]
        }
      ) do
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

  def coordinator(
        :internal,
        :create_validation_stamp,
        data = %{
          transaction: tx = %Transaction{address: tx_address},
          unspent_outputs: unspent_outputs,
          previous_chain: previous_chain,
          previous_storage_nodes: previous_storage_nodes,
          storage_nodes: storage_nodes,
          welcome_node_public_key: welcome_node_public_key,
          validation_nodes:
            validation_nodes = [
              %Node{last_public_key: coordinator_public_key} | cross_validation_nodes
            ],
          proof_of_work: pow_result
        }
      ) do
    Logger.info("Start validation stamp creation for #{tx_address |> Base.encode16()}")

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
    Task.Supervisor.async_stream(TaskSupervisor, cross_validation_nodes, fn node ->
      Network.send_message(node, [
        {:cross_validate, tx.address, stamp},
        {:set_replication_tree, tx.address, replication_tree}
      ])
    end)
    |> Stream.run()

    {:next_state, :waiting_cross_validation_stamps,
     data |> Map.put(:stamp, stamp) |> Map.put(:replication_tree, replication_tree)}
  end

  def waiting_cross_validation_stamps(
        :enter,
        :coordinator,
        _data = %{transaction: %Transaction{address: tx_address}}
      ) do
    Logger.info("End validation stamp creation for #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def waiting_cross_validation_stamps(
        :enter,
        :cross_validator,
        _data = %{transaction: %Transaction{address: tx_address}}
      ) do
    Logger.info("End cross validation for #{tx_address |> Base.encode16()}")
    :keep_state_and_data
  end

  def waiting_cross_validation_stamps(
        :cast,
        {:add_cross_validation_stamp, cross_validation_stamp = {_signature, _inconsistencies},
         from},
        data = %{validation_stamp: stamp, validation_nodes: [_ | cross_validation_nodes]}
      ) do
    if Stamp.valid_cross_validation_stamp?(cross_validation_stamp, stamp, from) do
      new_data =
        Map.update!(data, :cross_validation_stamps, &(&1 ++ [{from, cross_validation_stamp}]))

      %{cross_validation_stamps: stamps} = new_data

      # Wait to receive the all the cross validation stamps and to reach
      # the atomic commitment before to start replication
      if length(stamps) == length(cross_validation_nodes) do
        Enum.dedup_by(stamps, fn {_, inconsistencies} -> inconsistencies end)
        |> length
        |> case do
          1 ->
            {:next_state, :replication, new_data}

          _ ->
            {:next_state, :atomic_commitment_not_reach, new_data}
        end
      else
        {:keep_state, new_data}
      end
    else
      :keep_state_and_data
    end
  end

  def atomic_commitment_not_reach(
        :enter,
        _,
        _data = %{transaction: %Transaction{address: tx_address}}
      ) do
    Logger.error("Atomic commitment not reach for #{tx_address |> Base.encode16()}")

    # TODO: Malicious detection
    :keep_state_and_data
  end

  def replication(:enter, _, %{
        transaction: tx,
        validation_stamp: stamp,
        cross_validation_stamps: cross_validation_stamps,
        replication_nodes: replication_nodes
      }) do
    validated_transaction =
      tx
      |> Map.put(:validation_stamp, stamp)
      |> Map.put(:cross_validation_stamps, cross_validation_stamps)

    Task.Supervisor.async_stream(TaskSupervisor, replication_nodes, fn n ->
      Network.send_message(n, {:replicate_transaction, validated_transaction})
    end)
    |> Stream.run()

    :keep_state_and_data
  end

  def replication(:cast, {:add_cross_validation_stamp, _, _}, _data) do
    :keep_state_and_data
  end

  @spec add_cross_validation_stamp(
          binary(),
          {signature :: binary(), inconsistencies :: list(atom)},
          binary()
        ) ::
          :ok
  def add_cross_validation_stamp(
        tx_address,
        stamp = {_sig, _inconsistencies},
        validation_node_public_key
      ) do
    :gen_statem.cast(
      via_tuple(tx_address),
      {:add_cross_validation_stamp, stamp, validation_node_public_key}
    )
  end

  @spec set_replication_tree(binary(), list(bitstring())) :: :ok
  def set_replication_tree(tx_address, tree) do
    :gen_statem.cast(via_tuple(tx_address), {:set_replication_tree, tree})
  end

  @spec add_context(binary(), binary(), list(binary()), bitstring(), bitstring()) :: :ok
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
end
