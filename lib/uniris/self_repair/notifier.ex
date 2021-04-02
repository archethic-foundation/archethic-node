defmodule Uniris.SelfRepair.Notifier do
  @moduledoc false

  use GenServer

  alias Uniris.Crypto

  alias Uniris.PubSub

  alias Uniris.P2P
  alias Uniris.P2P.Message.ReplicateTransaction
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    PubSub.register_to_node_update()
    {:ok, []}
  end

  def handle_info(
        {:node_update, node = %Node{available?: true, first_public_key: first_public_key}},
        state
      ) do
    available_nodes = P2P.list_nodes(availability: :global)
    node_key = Crypto.node_public_key(0)

    TransactionChain.list_all([:address, :type])
    |> Stream.map(fn %Transaction{address: address, type: type} ->
      {address, type, Replication.chain_storage_nodes(address, type, available_nodes)}
    end)
    |> Stream.filter(fn {address, type, nodes} ->
      Replication.chain_storage_node?(
        address,
        type,
        first_public_key,
        nodes
      )
    end)
    |> Stream.each(fn {address, type, _nodes} ->
      previous_storage_nodes =
        Replication.chain_storage_nodes(
          address,
          type,
          Enum.reject(available_nodes, &(&1.first_public_key == first_public_key))
        )

      case previous_storage_nodes do
        [] ->
          :ok

        [%Node{first_public_key: first_public_key} | _] when first_public_key == node_key ->
          {:ok, tx} = TransactionChain.get_transaction(address)
          P2P.send_message!(node, %ReplicateTransaction{transaction: tx})
      end
    end)

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
