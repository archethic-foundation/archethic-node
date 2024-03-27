defmodule Archethic.Mining.DistributedWorkflow do
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

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining.Error
  alias Archethic.Mining.MaliciousDetection
  alias Archethic.Mining.PendingTransactionValidation
  alias Archethic.Mining.TransactionContext
  alias Archethic.Mining.ValidationContext
  alias Archethic.Mining.WorkflowRegistry

  alias Archethic.P2P
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.AddMiningContext
  alias Archethic.P2P.Message.CrossValidate
  alias Archethic.P2P.Message.CrossValidationDone
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.NotifyPreviousChain
  alias Archethic.P2P.Message.NotifyReplicationValidation
  alias Archethic.P2P.Message.ReplicationAttestationMessage
  alias Archethic.P2P.Message.ReplicatePendingTransactionChain
  alias Archethic.P2P.Message.ReplicateTransaction
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message.ValidateTransaction
  alias Archethic.P2P.Message.ValidationError
  alias Archethic.P2P.Message.UnlockChain
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

  require Logger

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter], restart: :temporary
  @vsn 1

  @mining_timeout Application.compile_env!(:archethic, [__MODULE__, :global_timeout])
  @coordinator_timeout_supplement Application.compile_env!(:archethic, [
                                    __MODULE__,
                                    :coordinator_timeout_supplement
                                  ])
  @context_notification_timeout Application.compile_env!(:archethic, [
                                  __MODULE__,
                                  :context_notification_timeout
                                ])

  def start_link(args \\ []) do
    GenStateMachine.start_link(__MODULE__, args, [])
  end

  @doc """
  Add transaction mining context which built by another cross validation node
  """
  @spec add_mining_context(
          worker_pid :: pid(),
          utxos_hashes :: list(binary()),
          validation_node_public_key :: Crypto.key(),
          previous_storage_nodes :: list(Node.t()),
          chain_storage_nodes_view :: bitstring(),
          beacon_storage_nodes_view :: bitstring(),
          io_storage_nodes_view :: bitstring()
        ) ::
          :ok
  def add_mining_context(
        pid,
        utxos_hashes,
        validation_node_public_key,
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      ) do
    GenStateMachine.cast(
      pid,
      {:add_mining_context, validation_node_public_key, previous_storage_nodes,
       chain_storage_nodes_view, beacon_storage_nodes_view, io_storage_nodes_view, utxos_hashes}
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
          },
          confirmed_cross_validation_nodes :: bitstring(),
          aggregated_utxos :: list(VersionedUnspentOutput.t())
        ) :: :ok
  def cross_validate(
        pid,
        stamp = %ValidationStamp{},
        replication_tree,
        confirmed_cross_validation_nodes,
        aggregated_utxos
      ) do
    GenStateMachine.cast(
      pid,
      {:cross_validate, stamp, replication_tree, confirmed_cross_validation_nodes,
       aggregated_utxos}
    )
  end

  @doc """
  Add a cross validation stamp to the transaction mining process
  """
  @spec add_cross_validation_stamp(worker_pid :: pid(), stamp :: CrossValidationStamp.t()) :: :ok
  def add_cross_validation_stamp(pid, stamp = %CrossValidationStamp{}) do
    GenStateMachine.cast(pid, {:add_cross_validation_stamp, stamp})
  end

  @doc """
  Add a replication validation in the mining process
  """
  @spec add_replication_validation(worker_pid :: pid(), node_public_key :: Crypto.key()) :: :ok
  def add_replication_validation(pid, node_public_key) do
    GenStateMachine.cast(pid, {:add_replication_validation, node_public_key})
  end

  @doc """
  Notify the replication failure from a validation node
  """
  @spec replication_error(pid :: pid(), error :: Error.t(), node_public_key :: Crypto.key()) ::
          :ok
  def replication_error(pid, error, node_public_key) do
    GenStateMachine.cast(pid, {:replication_error, error, node_public_key})
  end

  defp get_context_timeout(:hosting), do: Message.get_max_timeout()
  defp get_context_timeout(:oracle), do: @context_notification_timeout + 1_000
  defp get_context_timeout(_type), do: @context_notification_timeout

  defp get_coordinator_timeout(type),
    do: get_context_timeout(type) + @coordinator_timeout_supplement

  defp get_mining_timeout(type) when type == :hosting, do: @mining_timeout * 3
  defp get_mining_timeout(_type), do: @mining_timeout

  def init(opts \\ []) do
    tx = Keyword.get(opts, :transaction)
    welcome_node = Keyword.get(opts, :welcome_node)
    validation_nodes = Keyword.get(opts, :validation_nodes)
    node_public_key = Keyword.get(opts, :node_public_key)
    timeout = Keyword.get(opts, :timeout, get_mining_timeout(tx.type))
    contract_context = Keyword.get(opts, :contract_context)

    Registry.register(WorkflowRegistry, tx.address, [])

    Logger.info("Start mining",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    next_events = [
      {:next_event, :internal,
       {:start_mining, tx, welcome_node, validation_nodes, contract_context}},
      {{:timeout, :stop_timeout}, timeout, :any}
    ]

    {:ok, :idle, %{node_public_key: node_public_key, start_time: System.monotonic_time()},
     next_events}
  end

  def handle_event(
        :internal,
        {:start_mining, tx, welcome_node, validation_nodes, contract_context},
        :idle,
        data = %{node_public_key: node_public_key}
      ) do
    validation_time = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    authorized_nodes = P2P.authorized_and_available_nodes(validation_time)

    chain_storage_nodes = Election.chain_storage_nodes(tx.address, authorized_nodes)

    previous_address = Transaction.previous_address(tx)
    previous_storage_nodes = Election.chain_storage_nodes(previous_address, authorized_nodes)

    genesis_address_task =
      Task.async(fn ->
        TransactionChain.fetch_genesis_address(previous_address, previous_storage_nodes)
      end)

    resolved_addresses_task =
      Task.async(fn -> TransactionChain.resolve_transaction_addresses!(tx) end)

    [{:ok, genesis_address}, resolved_addresses] =
      Task.await_many([genesis_address_task, resolved_addresses_task])

    genesis_storage_nodes = Election.chain_storage_nodes(genesis_address, authorized_nodes)

    beacon_storage_nodes =
      tx.address
      |> BeaconChain.subset_from_address()
      |> Election.beacon_storage_nodes(BeaconChain.next_slot(validation_time), authorized_nodes)

    io_storage_nodes =
      if Transaction.network_type?(tx.type) do
        P2P.list_nodes()
      else
        resolved_addresses
        |> Map.values()
        |> Election.io_storage_nodes(authorized_nodes)
      end

    [coordinator_node = %Node{last_public_key: coordinator_key} | cross_validation_nodes] =
      validation_nodes

    context =
      ValidationContext.new(
        transaction: tx,
        welcome_node: welcome_node,
        coordinator_node: coordinator_node,
        cross_validation_nodes: cross_validation_nodes,
        chain_storage_nodes: chain_storage_nodes,
        beacon_storage_nodes: beacon_storage_nodes,
        io_storage_nodes: P2P.distinct_nodes(io_storage_nodes ++ genesis_storage_nodes),
        validation_time: validation_time,
        resolved_addresses: resolved_addresses,
        contract_context: contract_context,
        genesis_address: genesis_address
      )

    role = if node_public_key == coordinator_key, do: :coordinator, else: :cross_validator

    {:next_state, role, Map.put(data, :context, context),
     {:next_event, :internal, :build_transaction_context}}
  end

  def handle_event(:enter, :idle, :idle, _data = %{}) do
    :keep_state_and_data
  end

  def handle_event(
        :enter,
        :idle,
        :cross_validator,
        _data = %{context: %ValidationContext{transaction: tx}}
      ) do
    Logger.info("Act as cross validator",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

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

  def handle_event(
        :internal,
        :build_transaction_context,
        state,
        data = %{
          context:
            context = %ValidationContext{
              genesis_address: genesis_address,
              transaction: tx,
              chain_storage_nodes: chain_storage_nodes,
              beacon_storage_nodes: beacon_storage_nodes,
              io_storage_nodes: io_storage_nodes
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
     io_storage_nodes_view} =
      TransactionContext.get(
        Transaction.previous_address(tx),
        genesis_address,
        Enum.map(chain_storage_nodes, & &1.first_public_key),
        Enum.map(beacon_storage_nodes, & &1.first_public_key),
        Enum.map(io_storage_nodes, & &1.first_public_key)
      )

    now = System.monotonic_time()

    :telemetry.execute([:archethic, :mining, :fetch_context], %{
      duration: now - start
    })

    Logger.debug("Previous transaction #{inspect(prev_tx)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    Logger.debug("Unspent outputs #{inspect(unspent_outputs)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    new_context =
      ValidationContext.put_transaction_context(
        context,
        prev_tx,
        unspent_outputs,
        previous_storage_nodes,
        chain_storage_nodes_view,
        beacon_storage_nodes_view,
        io_storage_nodes_view
      )

    Logger.info("Transaction context retrieved",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    next_events =
      case state do
        :coordinator ->
          [{:next_event, :internal, :prior_validation}]

        :cross_validator ->
          [{:next_event, :internal, :notify_context}, {:next_event, :internal, :prior_validation}]
      end

    {:keep_state, %{data | context: new_context}, next_events}
  end

  def handle_event(:internal, :notify_context, :cross_validator, %{
        node_public_key: node_public_key,
        context: context
      }) do
    notify_transaction_context(context, node_public_key)
    :keep_state_and_data
  end

  def handle_event(
        :internal,
        :prior_validation,
        state,
        data = %{
          context: context = %ValidationContext{transaction: tx, validation_time: validation_time}
        }
      ) do
    new_context =
      case PendingTransactionValidation.validate(tx, validation_time) do
        :ok ->
          context

        {:error, error} ->
          Logger.debug("Invalid pending transaction - #{inspect(error)}",
            transaction_address: Base.encode16(tx.address),
            transaction_type: tx.type
          )

          ValidationContext.set_mining_error(context, error)
      end

    next_events =
      case state do
        :coordinator ->
          # TODO: Provide a better waiting time management
          # for example rolling percentile latency could be way to achieve this
          # (https://cs.stackexchange.com/a/129178)
          waiting_time = get_context_timeout(tx.type)

          Logger.debug(
            "Coordinator will wait #{waiting_time} ms before continue with the responding nodes",
            transaction_address: Base.encode16(tx.address),
            transaction_type: tx.type
          )

          [{{:timeout, :wait_confirmations}, waiting_time, :any}]

        :cross_validator ->
          [{{:timeout, :change_coordinator}, get_coordinator_timeout(tx.type), :any}]
      end

    {:keep_state, Map.put(data, :context, new_context), next_events}
  end

  def handle_event(
        :enter,
        :cross_validator,
        :coordinator,
        _data = %{context: %ValidationContext{transaction: tx}}
      ) do
    Logger.info("Change cross validator to coordinator due to timeout",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    actions = [{{:timeout, :wait_confirmations}, get_context_timeout(tx.type), :any}]

    {:keep_state_and_data, actions}
  end

  def handle_event(
        :cast,
        {:add_mining_context, from, previous_storage_nodes, chain_storage_nodes_view,
         beacon_storage_nodes_view, io_storage_nodes_view, utxos_hashes},
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
          chain_storage_nodes_view,
          beacon_storage_nodes_view,
          io_storage_nodes_view,
          from,
          utxos_hashes
        )

      if ValidationContext.enough_confirmations?(new_context) do
        Logger.info("Create validation stamp",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        {:keep_state, Map.put(data, :context, new_context),
         [
           {{:timeout, :wait_confirmations}, :cancel},
           {:next_event, :internal, :create_and_notify_validation_stamp}
         ]}
      else
        {:keep_state, %{data | context: new_context}}
      end
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        {:timeout, :wait_confirmations},
        :any,
        :coordinator,
        _data = %{context: %ValidationContext{transaction: tx}}
      ) do
    Logger.warning("Timeout to get the context validation nodes context is reached",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    Logger.warning("Validation stamp will be created with the confirmed cross validation nodes",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    {:keep_state_and_data, {:next_event, :internal, :create_and_notify_validation_stamp}}
  end

  def handle_event(
        :internal,
        :create_and_notify_validation_stamp,
        :coordinator,
        data = %{context: context = %ValidationContext{transaction: tx}}
      ) do
    case ValidationContext.get_confirmed_validation_nodes(context) do
      [] ->
        Logger.error("No cross validation nodes respond to confirm the mining context",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        notify_error(Error.new(:timeout), data)
        :stop

      _ ->
        new_context =
          context
          |> ValidationContext.create_validation_stamp()
          |> ValidationContext.create_replication_tree()

        request_cross_validations(new_context)
        {:next_state, :wait_cross_validation_stamps, %{data | context: new_context}}
    end
  end

  def handle_event(
        :cast,
        {:cross_validate, validation_stamp = %ValidationStamp{}, replication_tree,
         confirmed_cross_validation_nodes, aggregated_utxos},
        :cross_validator,
        data = %{
          node_public_key: node_public_key,
          context:
            context = %ValidationContext{
              transaction: tx
            }
        }
      ) do
    Logger.info("Cross validation",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    new_context =
      context
      |> ValidationContext.add_aggregated_utxos(aggregated_utxos)
      |> ValidationContext.set_confirmed_validation_nodes(confirmed_cross_validation_nodes)
      |> ValidationContext.add_validation_stamp(validation_stamp)
      |> ValidationContext.add_replication_tree(replication_tree, node_public_key)
      |> ValidationContext.cross_validate()

    notify_cross_validation_stamp(new_context)

    actions = [{{:timeout, :change_coordinator}, :cancel}]
    new_data = %{data | context: new_context}

    if ValidationContext.enough_cross_validation_stamps?(new_context) do
      if ValidationContext.atomic_commitment?(new_context) do
        {:next_state, :replication, new_data, actions}
      else
        {:next_state, :consensus_not_reached, new_data, actions}
      end
    else
      {:next_state, :wait_cross_validation_stamps, new_data, actions}
    end
  end

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
        from_state,
        :consensus_not_reached,
        data = %{
          context:
            context = %ValidationContext{
              transaction: tx,
              cross_validation_stamps: cross_validation_stamps,
              validation_stamp: validation_stamp
            }
        }
      )
      when from_state in [:cross_validator, :wait_cross_validation_stamps] do
    Logger.debug("Validation stamp: #{inspect(validation_stamp, limit: :infinity)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    Logger.debug("Cross validation stamps: #{inspect(cross_validation_stamps, limit: :infinity)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    Logger.error("Consensus not reached",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    MaliciousDetection.start_link(context)

    error_data =
      cross_validation_stamps
      |> Enum.flat_map(& &1.inconsistencies)
      |> Enum.uniq()
      |> Enum.map(&(&1 |> Atom.to_string() |> String.replace("_", " ")))

    notify_error(Error.new(:consensus_not_reached, error_data), data)
    :stop
  end

  def handle_event(
        :enter,
        from_state,
        :replication,
        data = %{
          node_public_key: node_public_key,
          context:
            context = %ValidationContext{
              mining_error: nil,
              transaction: %Transaction{address: tx_address, type: type}
            }
        }
      )
      when from_state in [:cross_validator, :wait_cross_validation_stamps] do
    Logger.info("Start replication",
      transaction_address: Base.encode16(tx_address),
      transaction_type: type
    )

    new_context = request_replication_validation(context, node_public_key)

    {:keep_state, %{data | context: new_context}}
  end

  def handle_event(
        :enter,
        from_state,
        :replication,
        data = %{context: %ValidationContext{mining_error: err}}
      )
      when from_state in [:cross_validator, :wait_cross_validation_stamps] do
    Logger.info("Skipped replication because validation failed: #{inspect(err)}")

    notify_error(err, data)
    :stop
  end

  def handle_event(
        :cast,
        {:add_replication_validation, node_public_key},
        :replication,
        data = %{context: context}
      ) do
    validation_nodes = ValidationContext.get_validation_nodes(context)

    if Utils.key_in_node_list?(validation_nodes, node_public_key) do
      new_context = ValidationContext.add_replication_validation(context, node_public_key)

      if ValidationContext.enough_replication_validations?(new_context) do
        request_replication(new_context)
      end

      {:keep_state, %{data | context: new_context}}
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:ack_replication, signature, node_public_key},
        :replication,
        data = %{
          start_time: start_time,
          context:
            context = %ValidationContext{
              transaction: %Transaction{address: address, type: type},
              validation_time: validation_time,
              genesis_address: genesis_address
            }
        }
      ) do
    with {:ok, node_index} <-
           ValidationContext.get_chain_storage_position(context, node_public_key),
         validated_tx <- ValidationContext.get_validated_transaction(context),
         tx_summary <- TransactionSummary.from_transaction(validated_tx, genesis_address),
         true <-
           Crypto.verify?(signature, TransactionSummary.serialize(tx_summary), node_public_key) do
      Logger.debug("Received ack storage",
        transaction_address: Base.encode16(address),
        transaction_type: type,
        node: Base.encode16(node_public_key)
      )

      new_context = ValidationContext.add_storage_confirmation(context, node_index, signature)

      if ValidationContext.enough_storage_confirmations?(new_context) do
        duration = System.monotonic_time() - start_time

        # send the mining_completed event
        Archethic.PubSub.notify_mining_completed(address, validation_time, duration, true)

        # metrics
        :telemetry.execute([:archethic, :mining, :full_transaction_validation], %{
          duration: duration
        })

        {:keep_state, %{data | context: new_context},
         [
           {:next_event, :internal, :notify_attestation},
           {:next_event, :internal, :notify_previous_chain}
         ]}
      else
        {:keep_state, %{data | context: new_context}}
      end
    else
      _ ->
        Logger.warning("Invalid storage ack",
          transaction_address: Base.encode16(address),
          transaction_type: type,
          node: Base.encode16(node_public_key)
        )

        :keep_state_and_data
    end
  end

  def handle_event(
        :internal,
        :notify_attestation,
        :replication,
        _data = %{
          context:
            context = %ValidationContext{
              welcome_node: welcome_node = %Node{},
              storage_nodes_confirmations: confirmations,
              genesis_address: genesis_address
            }
        }
      ) do
    validated_tx = ValidationContext.get_validated_transaction(context)
    tx_summary = TransactionSummary.from_transaction(validated_tx, genesis_address)

    message =
      ReplicationAttestationMessage.from_replication_attestation(%ReplicationAttestation{
        transaction_summary: tx_summary,
        confirmations: confirmations
      })

    beacon_storage_nodes = ValidationContext.get_beacon_replication_nodes(context)

    [welcome_node | beacon_storage_nodes]
    |> P2P.distinct_nodes()
    |> P2P.broadcast_message(message)

    validated_tx = ValidationContext.get_validated_transaction(context)

    context
    |> ValidationContext.get_io_replication_nodes()
    |> P2P.broadcast_message(%ReplicateTransaction{
      transaction: validated_tx,
      genesis_address: genesis_address
    })

    :keep_state_and_data
  end

  def handle_event(
        :internal,
        :notify_previous_chain,
        :replication,
        _data = %{
          context:
            context = %ValidationContext{
              transaction: tx
            }
        }
      ) do
    unless Transaction.network_type?(tx.type) do
      context
      |> ValidationContext.get_confirmed_replication_nodes()
      |> P2P.broadcast_message(%NotifyPreviousChain{address: tx.address})
    end

    :stop
  end

  def handle_event(
        :info,
        {:replication_error, error},
        :replication,
        data = %{
          context:
            context = %ValidationContext{transaction: tx, coordinator_node: coordinator_node},
          node_public_key: node_public_key
        }
      ) do
    Logger.error("Replication error - #{inspect(error)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    # Notify the other validations nodes about the replication error
    cross_validation_nodes = ValidationContext.get_confirmed_validation_nodes(context)

    validation_nodes =
      [coordinator_node | cross_validation_nodes]
      |> P2P.distinct_nodes()
      |> Enum.reject(&(&1.last_public_key == node_public_key))

    P2P.broadcast_message(validation_nodes, %ReplicationError{
      address: tx.address,
      error: error
    })

    notify_error(error, data)
    :stop
  end

  def handle_event(
        :cast,
        {:replication_error, error, from},
        :replication,
        data = %{context: context}
      ) do
    validation_nodes = ValidationContext.get_validation_nodes(context)

    if Utils.key_in_node_list?(validation_nodes, from) do
      notify_error(error, data)
      :stop
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        {:timeout, :change_coordinator},
        :any,
        :cross_validator,
        data = %{
          context:
            context = %ValidationContext{
              transaction: tx,
              cross_validation_nodes: validation_nodes
            },
          node_public_key: node_public_key
        }
      ) do
    [next_coordinator | next_cross_validation_nodes] = validation_nodes

    case next_cross_validation_nodes do
      [] ->
        Logger.error("No more cross validation nodes to used after coordinator timeout",
          transaction_address: Base.encode16(tx.address),
          transaction_type: tx.type
        )

        notify_error(Error.new(:timeout), data)
        :stop

      _ ->
        nb_cross_validation_nodes = length(next_cross_validation_nodes)

        new_context =
          context
          |> Map.put(:coordinator_node, next_coordinator)
          |> Map.put(:cross_validation_nodes, next_cross_validation_nodes)
          |> Map.put(:cross_validation_nodes_confirmation, <<0::size(nb_cross_validation_nodes)>>)

        if next_coordinator.last_public_key == node_public_key do
          {:next_state, :coordinator, %{data | context: new_context}}
        else
          actions = [
            {{:timeout, :change_coordinator}, get_coordinator_timeout(tx.type), :any},
            {:next_event, :internal, :notify_context}
          ]

          {:keep_state, %{data | context: new_context}, actions}
        end
    end
  end

  def handle_event(
        {:timeout, :stop_timeout},
        :any,
        state,
        data = %{
          start_time: start_time,
          context:
            context = %ValidationContext{
              validation_time: validation_time,
              transaction: %Transaction{address: address, type: type},
              storage_nodes_confirmations: confirmations
            }
        }
      ) do
    # Case when we received all replication validations, but some storage nodes didn't respond
    # with storage confirmation. We still notify received attestation and previous chain
    with :replication <- state,
         true <- ValidationContext.enough_replication_validations?(context),
         false <- Enum.empty?(confirmations) do
      Logger.warning("Didn't received all attestations before mining timeout",
        transaction_type: type,
        transaction_address: Base.encode16(address)
      )

      duration = System.monotonic_time() - start_time

      # send the mining_completed event
      Archethic.PubSub.notify_mining_completed(address, validation_time, duration, false)

      # metrics
      :telemetry.execute([:archethic, :mining, :full_transaction_validation], %{
        duration: duration
      })

      {:keep_state_and_data,
       [
         {:next_event, :internal, :notify_attestation},
         {:next_event, :internal, :notify_previous_chain}
       ]}
    else
      _ ->
        Logger.warning("Timeout reached during mining",
          transaction_type: type,
          transaction_address: Base.encode16(address)
        )

        notify_error(Error.new(:timeout), data)
        :stop
    end
  end

  def handle_event(
        event_type,
        event,
        state,
        _data = %{context: %ValidationContext{transaction: tx}}
      ) do
    Logger.warning(
      "Unexpected event #{inspect(event)}(#{inspect(event_type)}) in the state #{inspect(state)} - Will be postponed for the next state",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    {:keep_state_and_data, :postpone}
  end

  def code_change(_old_vsn, state, data, _extra), do: {:ok, state, data}

  defp notify_transaction_context(
         %ValidationContext{
           transaction: %Transaction{address: tx_address, type: tx_type},
           unspent_outputs: unspent_outputs,
           coordinator_node: coordinator_node,
           previous_storage_nodes: previous_storage_nodes,
           chain_storage_nodes_view: chain_storage_nodes_view,
           beacon_storage_nodes_view: beacon_storage_nodes_view,
           io_storage_nodes_view: io_storage_nodes_view
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
      utxos_hashes: Enum.map(unspent_outputs, &VersionedUnspentOutput.hash/1),
      validation_node_public_key: node_public_key,
      previous_storage_nodes_public_keys: Enum.map(previous_storage_nodes, & &1.last_public_key),
      chain_storage_nodes_view: chain_storage_nodes_view,
      beacon_storage_nodes_view: beacon_storage_nodes_view,
      io_storage_nodes_view: io_storage_nodes_view
    })
  end

  defp request_cross_validations(
         context = %ValidationContext{
           cross_validation_nodes_confirmation: cross_validation_node_confirmation,
           transaction: %Transaction{address: tx_address, type: tx_type},
           validation_stamp: validation_stamp,
           full_replication_tree: replication_tree,
           unspent_outputs: unspent_outputs
         }
       ) do
    cross_validation_nodes = ValidationContext.get_confirmed_validation_nodes(context)

    Logger.info(
      "Send validation stamp to #{Enum.map_join(cross_validation_nodes, ", ", &:inet.ntoa(&1.ip))}",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )

    P2P.broadcast_message(
      cross_validation_nodes,
      %CrossValidate{
        address: tx_address,
        validation_stamp: validation_stamp,
        replication_tree: replication_tree,
        confirmed_validation_nodes: cross_validation_node_confirmation,
        aggregated_utxos: unspent_outputs
      }
    )
  end

  defp notify_cross_validation_stamp(
         context = %ValidationContext{
           transaction: %Transaction{address: tx_address, type: tx_type},
           coordinator_node: coordinator_node,
           cross_validation_stamps: [cross_validation_stamp | []]
         }
       ) do
    cross_validation_nodes = ValidationContext.get_confirmed_validation_nodes(context)

    nodes =
      [coordinator_node | cross_validation_nodes]
      |> P2P.distinct_nodes()
      |> Enum.reject(&(&1.last_public_key == Crypto.last_node_public_key()))

    Logger.info(
      "Send cross validation stamps to #{Enum.map_join(nodes, ", ", &Node.endpoint/1)}",
      transaction_address: Base.encode16(tx_address),
      transaction_type: tx_type
    )

    P2P.broadcast_message(nodes, %CrossValidationDone{
      address: tx_address,
      cross_validation_stamp: cross_validation_stamp
    })
  end

  defp request_replication_validation(
         context = %ValidationContext{
           transaction: tx,
           coordinator_node: coordinator_node,
           contract_context: contract_context,
           aggregated_utxos: aggregated_utxos
         },
         node_public_key
       ) do
    storage_nodes = ValidationContext.get_chain_replication_nodes(context)

    Logger.info(
      "Send validated transaction to #{Enum.map_join(storage_nodes, ",", &Node.endpoint/1)} for replication's validation",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    validated_tx = ValidationContext.get_validated_transaction(context)

    message = %ValidateTransaction{
      transaction: validated_tx,
      contract_context: contract_context,
      inputs: aggregated_utxos
    }

    results =
      Task.Supervisor.async_stream_nolink(
        Archethic.TaskSupervisor,
        storage_nodes,
        &P2P.send_message(&1, message),
        ordered: false,
        on_timeout: :kill_task,
        timeout: Message.get_timeout(message) + 2000,
        max_concurrency: length(storage_nodes)
      )
      |> Stream.filter(&match?({:ok, {:ok, _}}, &1))
      |> Enum.map(fn {:ok, {:ok, res}} -> res end)

    if Enum.all?(results, &match?(%Ok{}, &1)) do
      cross_validation_nodes = ValidationContext.get_confirmed_validation_nodes(context)

      validation_nodes =
        [coordinator_node | cross_validation_nodes]
        |> P2P.distinct_nodes()
        |> Enum.reject(&(&1.last_public_key == node_public_key))

      Logger.info(
        "Send replication validation message to validation nodes: #{Enum.map_join(validation_nodes, ",", &Node.endpoint/1)}",
        transaction_address: Base.encode16(validated_tx.address),
        transaction_type: validated_tx.type
      )

      new_context = ValidationContext.add_replication_validation(context, node_public_key)

      P2P.broadcast_message(validation_nodes, %NotifyReplicationValidation{
        address: validated_tx.address
      })

      new_context
    else
      errors = Enum.filter(results, &match?(%ReplicationError{}, &1))

      case Enum.dedup(errors) do
        [%ReplicationError{error: error}] ->
          send(self(), {:replication_error, error})

        _ ->
          send(self(), {:replication_error, :invalid_atomic_commitment})
      end

      context
    end
  end

  defp request_replication(
         context = %ValidationContext{
           transaction: tx,
           genesis_address: genesis_address
         }
       ) do
    storage_nodes = ValidationContext.get_chain_replication_nodes(context)

    Logger.info(
      "Send validated transaction to #{Enum.map_join(storage_nodes, ",", &Node.endpoint/1)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    message = %ReplicatePendingTransactionChain{
      address: tx.address,
      genesis_address: genesis_address
    }

    P2P.broadcast_message(storage_nodes, message)
  end

  defp notify_error(error, %{
         context:
           context = %ValidationContext{
             welcome_node: welcome_node = %Node{},
             transaction: %Transaction{address: tx_address}
           }
       }) do
    Logger.warning("Invalid transaction #{inspect(error)}",
      transaction_address: Base.encode16(tx_address)
    )

    Logger.debug("Notify error back to the welcome node",
      transaction_address: Base.encode16(tx_address)
    )

    # Notify error to the welcome node
    message = %ValidationError{error: error, address: tx_address}

    Task.Supervisor.async_nolink(Archethic.TaskSupervisor, fn ->
      P2P.send_message(welcome_node, message)
      :ok
    end)

    # Notify storage nodes to unlock chain
    message = %UnlockChain{address: tx_address}

    context |> ValidationContext.get_chain_replication_nodes() |> P2P.broadcast_message(message)
  end
end
