defmodule UnirisSync do
  @moduledoc """
  Represents the synchronisation of the Uniris network by starting up the bootstrap process when a node startup,
  enable the self-repair mechanism and provide a notification system to acknowledge the storage of transactions.
  """

  alias UnirisChain.Transaction

  def subscribe_new_transaction() do
    Registry.register(UnirisSync.Registry, "new_transaction", [])
  end

  def subscribe_to(address) do
    Registry.register(UnirisSync.Registry, address, [])
  end

  def publish_new_transaction(tx = %Transaction{}) do
    Registry.dispatch(UnirisSync.Registry, "new_transaction", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:new_transaction, tx})
    end)

    Registry.dispatch(UnirisSync.Registry, tx.address, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:acknowledge_storage, tx.address})
    end)
  end

  def publish_storage(tx_address) do
    Registry.dispatch(UnirisSync.Registry, tx_address, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:acknowledge_storage, tx_address})
    end)
  end
end
