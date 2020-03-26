defmodule UnirisPubSub do

  alias UnirisChain.Transaction

  def notify_new_transaction(address) when is_binary(address) do
    Registry.dispatch(UnirisPubSub.Registry, "new_transaction", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:new_transaction, address})
    end)
  end

  def notify_new_transaction(tx = %Transaction{}) do
    Registry.dispatch(UnirisPubSub.Registry, "new_transaction", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:new_transaction, tx})
    end)
  end

  def register_to_new_transaction() do
    Registry.register(UnirisPubSub.Registry, "new_transaction", [])
  end
end
