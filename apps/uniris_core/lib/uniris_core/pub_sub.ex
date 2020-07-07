defmodule UnirisCore.PubSub do
  @moduledoc """
  Provide an internal publish/subscribe mechanism to be aware of the new transaction in the system.

  This PubSub is used for each application which deals with new transaction enter after validation,
  helping to rebuild their internal state and fast read-access (as an in memory storage)

  Processes can subscribe to new transaction either based on address or full transaction
  """

  alias UnirisCore.Transaction
  alias UnirisCore.P2P.Node
  alias UnirisCore.PubSubRegistry

  @doc """
  Notify the registered processes than a new transaction address has been validated
  """
  @spec notify_new_transaction(binary()) :: :ok
  def notify_new_transaction(address) when is_binary(address) do
    Registry.dispatch(PubSubRegistry, "new_transaction", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:new_transaction, address})
    end)
  end

  @doc """
  Notify the registered processes than a new transaction has been validated
  """
  @spec notify_new_transaction(Transaction.t()) :: :ok
  def notify_new_transaction(tx = %Transaction{}) do
    Registry.dispatch(PubSubRegistry, "new_transaction", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:new_transaction, tx})
    end)
  end

  @doc """
  Notify the registered processes than a node has been either updated or joined the network
  """
  @spec notify_node_update(Node.t()) :: :ok
  def notify_node_update(node = %Node{}) do
    Registry.dispatch(PubSubRegistry, "node_update", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:node_update, node})
    end)
  end

  @doc """
  Register a process to a new transaction publication
  """
  @spec register_to_new_transaction() :: {:ok, pid()}
  def register_to_new_transaction() do
    Registry.register(PubSubRegistry, "new_transaction", [])
  end

  @doc """
  Register a process to a node update publication
  """
  @spec register_to_node_update() :: :ok
  def register_to_node_update() do
    Registry.register(PubSubRegistry, "node_update", [])
  end
end
