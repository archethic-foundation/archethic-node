defmodule UnirisCore.PubSub do
  @moduledoc """
  Provide an internal publish/subscribe mechanism to be aware of the new transaction in the system.

  This PubSub is used for each application which deals with new transaction enter after validation,
  helping to rebuild their internal state and fast read-access (as an in memory storage)

  Processes can subscribe to new transaction either based on address or full transaction
  """

  alias UnirisCore.Transaction
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
  @spec notify_new_transaction(Transaction.validated()) :: :ok
  def notify_new_transaction(tx = %Transaction{}) do
    Registry.dispatch(PubSubRegistry, "new_transaction", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:new_transaction, tx})
    end)
  end

  @doc """
  Register a process to a new transaction publication
  """
  @spec register_to_new_transaction() :: {:ok, pid()}
  def register_to_new_transaction() do
    Registry.register(PubSubRegistry, "new_transaction", [])
  end
end
