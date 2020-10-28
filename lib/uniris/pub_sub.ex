defmodule Uniris.PubSub do
  @moduledoc """
  Provide an internal publish/subscribe mechanism to be aware of the new transaction in the system.

  This PubSub is used for each application which deals with new transaction enter after validation,
  helping to rebuild their internal state and fast read-access (as an in memory storage)

  Processes can subscribe to new transaction either based on address or full transaction
  """

  alias Uniris.P2P.Node

  alias Uniris.PubSubRegistry

  alias Uniris.TransactionChain.Transaction

  @doc """
  Notify the registered processes than a new transaction has been validated
  """
  @spec notify_new_transaction(binary(), Transaction.type(), DateTime.t()) :: :ok
  def notify_new_transaction(address, type, timestamp = %DateTime{})
      when is_binary(address) and is_atom(type) do
    dispatch(:new_transaction, {:new_transaction, address, type, timestamp})
    dispatch({:new_transaction, address}, {:new_transaction, address})
    dispatch({:new_transaction, type}, {:new_transaction, address, type})
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

  @doc """
  Register a process to a new transaction publication by type
  """
  @spec register_to_new_transaction_by_type(Transaction.type()) :: {:ok, pid()}
  def register_to_new_transaction_by_type(type) when is_atom(type) do
    Registry.register(PubSubRegistry, {:new_transaction, type}, [])
  end

  @doc """
  Register a process to a new transaction publication by address
  """
  @spec register_to_new_transaction_by_address(binary()) :: {:ok, pid()}
  def register_to_new_transaction_by_address(address) when is_binary(address) do
    Registry.register(PubSubRegistry, {:new_transaction, address}, [])
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

  defp dispatch(topic, message) do
    Registry.dispatch(PubSubRegistry, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end
end
