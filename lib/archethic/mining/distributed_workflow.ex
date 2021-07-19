defmodule ArchEthic.Mining.DistributedWorkflow do
  @moduledoc """
  ARCH mining workflow is performed in distributed manner through a Finite State Machine
  to ensure consistency of the actions and be able to postpone concurrent events and manage timeout

  Every transaction mining follows these steps:
  - Mining Context retrieval (previous tx, UTXOs, P2P view of chain/beacon storage nodes, cross validation nodes) (from everyone)
  - Mining context notification (from cross validators, to coordinator)
  - Validation stamp and replication tree creation (from coordinator, to cross validators)
  - Cross validation of the validation stamp (from cross validators, to coordinator)
  - Replication (once the atomic commitment is reached) (from everyone, to the dedicated storage nodes)

  If the atomic commitment is not reached, it starts the malicious detection to ban the dishonest nodes
  """

  alias ArchEthic.Crypto

  alias ArchEthic.Mining.MaliciousDetection
  alias ArchEthic.Mining.PendingTransactionValidation
  alias ArchEthic.Mining.TransactionContext
  alias ArchEthic.Mining.ValidationContext
  alias ArchEthic.Mining.WorkflowRegistry

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.AddMiningContext
  alias ArchEthic.P2P.Message.CrossValidate
  alias ArchEthic.P2P.Message.CrossValidationDone
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Message.ReplicateTransaction
  alias ArchEthic.P2P.Node

  alias ArchEthic.Replication

  alias ArchEthic.TaskSupervisor

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp

  require Logger

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter], restart: :transient

  @mining_timeout Application.compile_env!(:archethic, [ArchEthic.Mining, :timeout])

  def start_link(args \\ []) do
    GenStateMachine.start_link(__MODULE__, args, [])
  end

  @doc """
  Add transaction mining context which built by another cross validation node
  """
  @spec add_mining_context(
          worker_pid :: pid(),
          validation_node_public_key :: Crypto.key(),
          previous_storage_nodes :: list(Node.t()),
          cross_validation_nodes_view :: bitstring(),
          chain_storage_nodes_view :: bitstring(),
          beacon_storage_nodes_view :: bitstring()
        ) ::
          :ok
  def add_mining_context(
        pid,
        validation_node_public_key,
        previous_storage_nodes,
        cross_validation_nodes_view,
        chain_storage_nodes_view,
        beacon_storage_nodes_view
      ) do
    GenStateMachine.cast(
      pid,
      {:add_mining_context, validation_node_public_key, previous_storage_nodes,
       cross_validation_nodes_view, chain_storage_nodes_view, beacon_storage_nodes_view}
    )
  end

  @doc """
  Cross validate the validation stamp and the replication tree produced by the coordinator

  If no inconsistencies, the validation stamp is stamped by the the node public key.
  Otherwise the inconsistencies will be signed.
  """
  @spec cross_validate(
          worker_pid :: pid(),
          ValidationStamp.t(),
          replication_tree :: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          }
        ) :: :ok
  def cross_validate(pid, stamp = %ValidationStamp{}, replication_tree) do
    GenStateMachine.cast(pid, {:cross_validate, stamp, replication_tree})
  end

  @doc """
  Add a cross validation stamp to the transaction mining process
  """
  @spec add_cross_validation_stamp(worker_pid :: pid(), stamp :: CrossValidationStamp.t()) :: :ok
  def add_cross_validation_stamp(pid, stamp = %CrossValidationStamp{}) do
    GenStateMachine.cast(pid, {:add_cross_validation_stamp, stamp})
  end

  def init(opts) do
    {tx, welcome_node, validation_nodes, node_public_key, timeout} = parse_opts(opts)

    Registry.register(WorkflowRegistry, tx.address, [])

    Logger.info("Start mining",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    chain_storage_nodes =
      Replication.chain_storage_nodes_with_type(
        tx.address,
        tx.type,
        P2P.authorized_nodes() |> Enum.filter(& &1.available?)
      )

    beacon_storage_nodes =
      Replication.beacon_storage_nodes(
        tx.address,
        DateTime.utc_now(),
        P2P.authorized_nodes() |> Enum.filter(& &1.available?)
      )

    context =
      ValidationContext.new(
        transaction: tx,
        welcome_node: welcome_node,
        validation_nodes: validation_nodes,
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes
      )

    next_events = [
      {{:timeout, :stop_timeout}, timeout, :any},
      {:next_event, :internal, :prior_validation}
    ]

    {:ok, :idle,
     %{node_public_key: node_public_key, context: context, start_time: System.monotonic_time()},
     next_events}
  end

  defp parse_opts(opts) do
    tx = Keyword.get(opts, :transaction)
    welcome_node = Keyword.get(opts, :welcome_node)
    validation_nodes = Keyword.get(opts, :validation_nodes)
    node_public_key = Keyword.get(opts, :node_public_key)
    timeout = Keyword.get(opts, :timeout, @mining_timeout)

    {tx, welcome_node, validation_nodes, node_public_key, timeout}
  end

  def handle_event(:enter, :idle, :idle, _data = %{context: %ValidationContext{transaction: tx}}) do
    Logger.info("Validation started",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    :keep_state_and_data
  end

  def handle_event(
        :internal,
        :prior_validation,
        :idle,
        data = %{
          node_public_key: node_public_key,
          context:
            context = %ValidationContext{
              transaction: tx,
              coordinator_node: %Node{last_public_key: coordinator_key}
            }
        }
      ) do
    role = if node_public_key == coordinator_key, do: :coordinator, else: :cross_validator

    case PendingTransactionValidation.validate(tx) do
      :ok ->
        new_data =
          Map.put(
            data,
            :context,
            ValidationContext.set_pending_transaction_validation(context, true)
          )

        next_events =
          case role do
            :cross_validator ->
              [
                {:next_event, :internal, :build_transaction_context},
                {:next_event, :internal, :notify_context}
              ]

            :coordinator ->
              [{:next_event, :internal, :build_transaction_context}]
          end

        {:next_state, role, new_data, next_events}

      _ ->
        new_data =
          Map.put(
            data,
            :context,
            ValidationContext.set_pending_transaction_validation(context, false)
          )

        case role do
          :coordinator ->
            {:next_state, :coordinator, new_data,
             {:next_event, :internal, :create_and_notify_validation_stamp}}

          :cross_validator ->
            {:next_state, :cross_validator, new_data}
        end
    end
  end

  def handle_event(
        :internal,
        :build_transaction_context,
        _,
        data = %{
          context:
            context = %ValidationContext{
              transaction: tx,
              coordinator_node: %Node{last_public_key: coordinator_key},
              chain_storage_nodes: chain_storage_nodes,
              beacon_storage_nodes: beacon_storage_nodes,
              cross_validation_nodes: cross_validation_nodes
            }
        }
      ) do
    Logger.info("Retrieve transaction context",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    start = System.monotonic_time()

    {prev_tx, unspent_outputs, previous_storage_nodes, chain_storage_nodes_view,
     beacon_storage_nodes_view,
     validation_nodes_view} =
      TransactionContext.get(
        Transaction.previous_address(tx),
        Enum.map(chain_storage_nodes, & &1.last_public_key),
        Enum.map(beacon_storage_nodes, & &1.last_public_key),
        [coordinator_key | Enum.map(cross_validation_nodes, & &1.last_public_key)]
      )

    :telemetry.execute([:archethic, :mining, :fetch_context], %{
      duration: System.monotonic_time() - start
    })

    new_context =
      ValidationContext.put_transaction_context(
        context,
        prev_tx,
        unspent_outputs,
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        validation_nodes_view
      )

    Logger.info("Transaction context retrieved",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    {:keep_state, %{data | context: new_context}}
  end

  def handle_event(
        :enter,
        :idle,
        :cross_validator,
        _data = %{
          context: %ValidationContext{transaction: tx}
        }
      ) do
    Logger.info("Act as cross validator",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    :keep_state_and_data
  end

  def handle_event(:internal, :notify_context, :cross_validator, %{
        node_public_key: node_public_key,
        context: context
      }) do
    notify_transaction_context(context, node_public_key)
    :keep_state_and_data
  end

  def handle_event(
        :enter,
        :idle,
        :coordinator,
        _data = %{context: %ValidationContext{transaction: tx}}
      ) do
    Logger.info("Act as coordinator",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    :keep_state_and_data
  end

  def handle_event(:cast, {:add_mining_context, _, _, _, _, _}, :idle, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:add_mining_context, from, previous_storage_nodes, validation_nodes_view,
         chain_storage_nodes_view, beacon_storage_nodes_view},
        :coordinator,
        data = %{
          context:
            context = %ValidationContext{
              transaction: tx
            }
        }
      ) do
    Logger.info("Aggregate mining context",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    if ValidationContext.cross_validation_node?(context, from) do
      new_context =
        ValidationContext.aggregate_mining_context(
          context,
          previous_storage_nodes,
          validation_nodes_view,
          chain_storage_nodes_view,
          beacon_storage_nodes_view,
          from
        )

      if ValidationContext.enough_confirmations?(new_context) do
        Logger.info("Create validation stamp",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:keep_state, Map.put(data, :context, new_context),
         {:next_event, :internal, :create_and_notify_validation_stamp}}
      else
        {:keep_state, %{data | context: new_context}}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(:internal, :create_and_notify_validation_stamp, _, data = %{context: context}) do
    new_context =
      context
      |> ValidationContext.create_validation_stamp()
      |> ValidationContext.create_replication_tree()

    request_cross_validations(new_context)
    {:next_state, :wait_cross_validation_stamps, %{data | context: new_context}}
  end

  def handle_event(:cast, {:cross_validate, _}, :idle, _), do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:cross_validate, validation_stamp = %ValidationStamp{}, replication_tree},
        :cross_validator,
        data = %{
          node_public_key: node_public_key,
          context:
            context = %ValidationContext{
              transaction: tx,
              cross_validation_nodes: cross_validation_nodes
            }
        }
      ) do
    Logger.info("Cross validation",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    new_context =
      context
      |> ValidationContext.add_validation_stamp(validation_stamp)
      |> ValidationContext.add_replication_tree(replication_tree, node_public_key)
      |> ValidationContext.cross_validate()

    notify_cross_validation_stamp(new_context)

    if length(cross_validation_nodes) == 1 and ValidationContext.atomic_commitment?(new_context) do
      {:next_state, :replication, %{data | context: new_context}}
    else
      {:next_state, :wait_cross_validation_stamps, %{data | context: new_context}}
    end
  end

  def handle_event(:cast, {:add_cross_validation_stamp, _}, :cross_validator, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :enter,
        _,
        :wait_cross_validation_stamps,
        _data = %{context: %ValidationContext{transaction: tx}}
      ) do
    Logger.info("Waiting cross validation stamps",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    :keep_state_and_data
  end

  def handle_event(
        :cast,
        {:add_cross_validation_stamp, cross_validation_stamp = %CrossValidationStamp{}},
        :wait_cross_validation_stamps,
        data = %{
          context: context = %ValidationContext{transaction: tx}
        }
      ) do
    Logger.info("Add cross validation stamp",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    new_context = ValidationContext.add_cross_validation_stamp(context, cross_validation_stamp)

    if ValidationContext.enough_cross_validation_stamps?(new_context) do
      if ValidationContext.atomic_commitment?(new_context) do
        {:next_state, :replication, %{data | context: new_context}}
      else
        {:next_state, :consensus_not_reached, %{data | context: new_context}}
      end
    else
      {:keep_state, %{data | context: new_context}}
    end
  end

  def handle_event(
        :enter,
        :wait_cross_validation_stamps,
        :consensus_not_reached,
        _data = %{context: context = %ValidationContext{transaction: tx}}
      ) do
    Logger.error("Consensus not reached - Malicious Detection started",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    MaliciousDetection.start_link(context)
    :stop
  end

  def handle_event(
        :enter,
        :wait_cross_validation_stamps,
        :replication,
        _data = %{
          context:
            context = %ValidationContext{
              transaction: %Transaction{address: tx_address, type: type}
            }
        }
      ) do
    Logger.info("Start replication",
      transaction_address: Base.encode16(tx_address),
      transaction_type: type
    )

    request_replication(context)
    :keep_state_and_data
  end

  def handle_event(
        :enter,
        :cross_validator,
        :replication,
        _data = %{
          context:
            context = %ValidationContext{
              transaction: %Transaction{address: tx_address, type: tx_type},
              cross_validation_nodes: [_]
            }
        }
      ) do
    Logger.info("Start replication",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )

    request_replication(context)
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:acknowledge_storage, replication_node_public_key, tree_types},
        :replication,
        data = %{context: context = %ValidationContext{transaction: tx}, start_time: start_time}
      ) do
    new_context =
      ValidationContext.confirm_replication(context, replication_node_public_key, tree_types)

    if ValidationContext.enough_replication_confirmations?(new_context) do
      :telemetry.execute([:archethic, :mining, :full_transaction_validation], %{
        duration: System.monotonic_time() - start_time
      })

      Logger.info("Replication finished",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      :stop
    else
      {:keep_state, %{data | context: new_context}}
    end
  end

  def handle_event(
        {:timeout, :stop_timeout},
        :any,
        _state,
        _data = %{context: %ValidationContext{transaction: tx}}
      ) do
    Logger.warning("Timeout reached during mining",
      transaction_type: tx.type,
      transaction_address: Base.encode16(tx.address)
    )

    :stop
  end

  # Reject unexpected events
  def handle_event(_, _, _, _), do: :keep_state_and_data

  defp notify_transaction_context(
         %ValidationContext{
           transaction: %Transaction{address: tx_address, type: tx_type},
           coordinator_node: coordinator_node,
           previous_storage_nodes: previous_storage_nodes,
           validation_nodes_view: validation_nodes_view,
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view
         },
         node_public_key
       ) do
    Logger.info(
      "Send mining context to #{Node.endpoint(coordinator_node)}",
      transaction_type: tx_type,
      transaction_address: Base.encode16(tx_address)
    )

    P2P.send_message(coordinator_node, %AddMiningContext{
      address: tx_address,
      validation_node_public_key: node_public_key,
      previous_storage_nodes_public_keys: Enum.map(previous_storage_nodes, & &1.last_public_key),
      validation_nodes_view: validation_nodes_view,
      chain_storage_nodes_view: chain_storage_nodes_view,
      beacon_storage_nodes_view: beacon_storage_nodes_view
    })
  end

  defp request_cross_validations(%ValidationContext{
         cross_validation_nodes: cross_validation_nodes,
         transaction: %Transaction{address: tx_address, type: tx_type},
         validation_stamp: validation_stamp,
         full_replication_tree: replication_tree
       }) do
    Logger.info(
      "Send validation stamp to #{cross_validation_nodes |> Enum.map(&:inet.ntoa(&1.ip)) |> Enum.join(", ")}",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )

    P2P.broadcast_message(cross_validation_nodes, %CrossValidate{
      address: tx_address,
      validation_stamp: validation_stamp,
      replication_tree: replication_tree
    })
  end

  defp notify_cross_validation_stamp(%ValidationContext{
         transaction: %Transaction{address: tx_address, type: tx_type},
         coordinator_node: coordinator_node,
         cross_validation_nodes: cross_validation_nodes,
         cross_validation_stamps: [cross_validation_stamp | []]
       }) do
    nodes =
      [coordinator_node | cross_validation_nodes]
      |> P2P.distinct_nodes()
      |> Enum.reject(&(&1.last_public_key == Crypto.last_node_public_key()))

    Logger.info(
      "Send cross validation stamps to #{nodes |> Enum.map(&Node.endpoint/1) |> Enum.join(", ")}",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )

    P2P.broadcast_message(nodes, %CrossValidationDone{
      address: tx_address,
      cross_validation_stamp: cross_validation_stamp
    })
  end

  defp request_replication(
         context = %ValidationContext{
           transaction: tx,
           welcome_node: %Node{last_public_key: welcome_node_public_key}
         }
       ) do
    storage_nodes = ValidationContext.get_replication_nodes(context)

    worker_pid = self()

    Logger.info(
      "Send validated transaction to #{storage_nodes |> Enum.map(fn {node, roles} -> "#{Node.endpoint(node)} as #{Enum.join(roles, ",")}" end) |> Enum.join(",")}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    validated_tx = ValidationContext.get_validated_transaction(context)

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      storage_nodes,
      fn {node, roles} ->
        message = %ReplicateTransaction{
          transaction: validated_tx,
          roles: roles,
          ack_storage?: true,
          welcome_node_public_key: welcome_node_public_key
        }

        case P2P.send_message(node, message) do
          {:ok, %Ok{}} ->
            {:ok, node, roles}

          _ ->
            :error
        end
      end,
      on_timeout: :kill_task,
      ordered?: false
    )
    |> Stream.filter(&match?({:ok, {:ok, %Node{}, _}}, &1))
    |> Stream.each(fn {:ok, {:ok, %Node{last_public_key: node_key}, roles}} ->
      send(worker_pid, {:acknowledge_storage, node_key, roles})
    end)
    |> Stream.run()
  end
end
