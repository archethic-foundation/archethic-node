defmodule UnirisCore do

  alias __MODULE__.P2P
  alias __MODULE__.P2P.Node
  alias __MODULE__.Election
  alias __MODULE__.Transaction
  alias __MODULE__.Crypto
  alias __MODULE__.Beacon
  alias __MODULE__.BeaconSlot

  @doc """
  Query the search of the transaction to the dedicated storage pool
  """
  @spec search_transaction(address :: binary()) :: {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def search_transaction(address) when is_binary(address) do
    %Node{network_patch: patch} = P2P.node_info()

    nearest_node = address
    |> Election.storage_nodes()
    |> P2P.nearest_nodes(patch)
    |> List.first()
    |> P2P.send_message({:get_transaction, address})
  end

  @doc """
  Send a new transaction in the network to be mined. The current node will act as welcome node
  """
  @spec send_new_transaction(Transaction.pending()) :: :ok
  def send_new_transaction(tx = %Transaction{}) do
    validation_nodes = Election.validation_nodes(tx)
    Enum.each(validation_nodes, fn node ->
      Task.start(fn ->
        P2P.send_message(
          node,
          {:start_mining, tx, Crypto.node_public_key(),
            Enum.map(validation_nodes, & &1.last_public_key)}
        )
      end)
    end)
  end

end
