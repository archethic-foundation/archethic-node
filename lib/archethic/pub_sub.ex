defmodule Archethic.PubSub do
  @moduledoc """
  Provide an internal publish/subscribe mechanism to be aware of the new transaction in the system.

  This PubSub is used for each application which deals with new transaction enter after validation,
  helping to rebuild their internal state and fast read-access (as an in memory storage)

  Processes can subscribe to new transaction either based on address or full transaction
  """

  alias Archethic.BeaconChain.ReplicationAttestation

  alias Archethic.P2P.Node

  alias Archethic.PubSubRegistry

  alias Archethic.TransactionChain.Transaction

  alias Archethic.TransactionChain.TransactionSummary

  @doc """
  Notify the registered processes than a new transaction has been validated
  """
  @spec notify_new_transaction(binary(), Transaction.transaction_type(), DateTime.t()) :: :ok
  def notify_new_transaction(address, type, timestamp = %DateTime{})
      when is_binary(address) and is_atom(type) do
    dispatch(:new_transaction, {:new_transaction, address, type, timestamp})
    dispatch({:new_transaction, address}, {:new_transaction, address, type, timestamp})
    dispatch({:new_transaction, type}, {:new_transaction, address, type, timestamp})
  end

  def notify_new_transaction(address) when is_binary(address) do
    dispatch(:new_transaction, {:new_transaction, address})
    dispatch({:new_transaction, address}, {:new_transaction, address})
  end

  @doc """
  Notify the registered processes than a node has been either updated or joined the network
  """
  @spec notify_node_update(Node.t()) :: :ok
  def notify_node_update(node = %Node{}) do
    dispatch(:node_update, {:node_update, node})
  end

  def notify_code_proposal_deployment(address, p2p_port, web_port)
      when is_binary(address) and is_integer(p2p_port) and is_integer(web_port) do
    dispatch(
      :code_proposal_deployment,
      {:proposal_deployment, address, p2p_port, web_port}
    )

    dispatch(
      {:code_proposal_deployment, address},
      {:proposal_deployment, address, p2p_port, web_port}
    )
  end

  def notify_new_tps(tps, nb_transactions) when is_float(tps) and is_integer(nb_transactions) do
    dispatch(:new_tps, {:new_tps, tps, nb_transactions})
  end

  @doc """
  Notify new oracle data to the subscribers
  """
  @spec notify_new_oracle_data(binary()) :: :ok
  def notify_new_oracle_data(data) do
    dispatch(:new_oracle_data, {:new_oracle_data, data})
  end

  @doc """
  Notify next summary time beacon chain to the subscribers
  """
  def notify_next_summary_time(date = %DateTime{}) do
    dispatch(:next_summary_time, {:next_summary_time, date})
  end

  @doc """
  Notify next epoch of slot time
  """
  def notify_current_epoch_of_slot_timer(date = %DateTime{}) do
    dispatch(:current_epoch_of_slot_timer, {:current_epoch_of_slot_timer, date})
  end

  @doc """
  Notify a new transaction replication attestation received
  """
  @spec notify_replication_attestation(ReplicationAttestation.t()) :: :ok
  def notify_replication_attestation(attestation = %ReplicationAttestation{}) do
    dispatch(
      :new_replication_attestation,
      {:new_replication_attestation, attestation}
    )
  end

  @doc """
  Notify a new transaction  attestation for beacon explorer
  """
  @spec notify_transaction_attestation(TransactionSummary.t()) :: :ok
  def notify_transaction_attestation(attestation = %TransactionSummary{}) do
    dispatch(
      :new_transaction_attestation,
      {:new_transaction_attestation, attestation}
    )
  end

  @doc """
  Notify Node status (up or down)
  """
  @spec notify_node_status(:node_up | :node_down) :: :ok
  def notify_node_status(status), do: dispatch(:node_status, status)

  @spec register_to_node_status :: {:error, {:already_registered, pid}} | {:ok, pid}
  @doc """
  Register a process to notify node status
  """
  def register_to_node_status(), do: Registry.register(PubSubRegistry, :node_status, [])

  @doc """
  Notify that a self repair synchronization is starting
  """
  @spec notify_self_repair() :: :ok
  def notify_self_repair(), do: dispatch(:self_repair_sync, :self_repair_sync)

  @doc """
  Register a process to self repair synchronizations starts
  """
  @spec register_to_self_repair :: {:error, {:already_registered, pid}} | {:ok, pid}
  def register_to_self_repair(), do: Registry.register(PubSubRegistry, :self_repair_sync, [])

  @doc """
  Register a process to a new transaction publication by type
  """
  @spec register_to_new_transaction_by_type(Transaction.transaction_type()) :: {:ok, pid()}
  def register_to_new_transaction_by_type(type) when is_atom(type) do
    Registry.register(PubSubRegistry, {:new_transaction, type}, [])
  end

  @doc """
  Unregister a process to a new transaction publication by type
  """
  @spec unregister_to_new_transaction_by_type(Transaction.transaction_type()) :: :ok
  def unregister_to_new_transaction_by_type(type) when is_atom(type) do
    Registry.unregister(PubSubRegistry, {:new_transaction, type})
  end

  @doc """
  Register a process to a new transaction publication by address
  """
  @spec register_to_new_transaction_by_address(binary()) :: {:ok, pid()}
  def register_to_new_transaction_by_address(address) when is_binary(address) do
    Registry.register(PubSubRegistry, {:new_transaction, address}, [])
  end

  @doc """
  Unregister a process to a new transaction publication by address
  """
  @spec unregister_to_new_transaction_by_address(binary()) :: :ok
  def unregister_to_new_transaction_by_address(address) when is_binary(address) do
    Registry.unregister(PubSubRegistry, {:new_transaction, address})
  end

  @doc """
  Register a process to a new transaction publication
  """
  @spec register_to_new_transaction() :: {:ok, pid()}
  def register_to_new_transaction do
    Registry.register(PubSubRegistry, :new_transaction, [])
  end

  @doc """
  Register a process to a node update publication
  """
  @spec register_to_node_update() :: {:ok, pid()}
  def register_to_node_update do
    Registry.register(PubSubRegistry, :node_update, [])
  end

  @spec unregister_to_node_update() :: :ok
  def unregister_to_node_update do
    Registry.unregister(PubSubRegistry, :node_update)
  end

  @doc """
  Register a process to a code deployment publication
  """
  @spec register_to_code_proposal_deployment() :: {:ok, pid()}
  def register_to_code_proposal_deployment do
    Registry.register(PubSubRegistry, :code_proposal_deployment, [])
  end

  @doc """
  Register a process to a code deployment publication for a given transaction address
  """
  @spec register_to_code_proposal_deployment(address :: binary()) :: {:ok, pid()}
  def register_to_code_proposal_deployment(address) when is_binary(address) do
    Registry.register(PubSubRegistry, {:code_proposal_deployment, address}, [])
  end

  @doc """
  Register a process to a new TPS
  """
  @spec register_to_new_tps :: {:ok, pid()}
  def register_to_new_tps do
    Registry.register(PubSubRegistry, :new_tps, [])
  end

  @doc """
  Register a process to sent next summary time of beacon summary
  """
  @spec register_to_next_summary_time :: {:ok, pid()}
  def register_to_next_summary_time do
    Registry.register(PubSubRegistry, :next_summary_time, [])
  end

  @doc """
  Register a process to sent current epoch of slot time
  """
  @spec register_to_current_epoch_of_slot_time :: {:ok, pid()}
  def register_to_current_epoch_of_slot_time do
    Registry.register(PubSubRegistry, :current_epoch_of_slot_timer, [])
  end

  @doc """
  Register to a new oracle data
  """
  @spec register_to_oracle_data :: {:ok, pid()}
  def register_to_oracle_data do
    Registry.register(PubSubRegistry, :new_oracle_data, [])
  end

  @doc """
  Register to new replication attestations
  """
  def register_to_new_replication_attestations do
    Registry.register(PubSubRegistry, :new_replication_attestation, [])
  end

  @doc """
  Register to new transaction attestations for beacon explorer
  """
  def register_to_new_transaction_attestations do
    Registry.register(PubSubRegistry, :new_transaction_attestation, [])
  end

  defp dispatch(topic, message) do
    Registry.dispatch(PubSubRegistry, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end
end
