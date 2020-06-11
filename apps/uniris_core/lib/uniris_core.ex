defmodule UnirisCore do
  alias __MODULE__.P2P
  alias __MODULE__.P2P.Node
  alias __MODULE__.Election
  alias __MODULE__.Transaction
  alias __MODULE__.Crypto
  alias __MODULE__.Storage

  @doc """
  Query the search of the transaction to the dedicated storage pool
  """
  @spec search_transaction(address :: binary()) ::
          {:ok, Transaction.validated()} | {:error, :transaction_not_exists}
  def search_transaction(address) when is_binary(address) do
    case Storage.get_transaction(address) do
      {:ok, tx} ->
        {:ok, tx}

      _ ->
        {:ok, %Node{network_patch: patch}} = P2P.node_info()

        address
        |> Election.storage_nodes()
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message({:get_transaction, address})
    end
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

  @spec get_last_transaction(address :: binary()) ::
          {:ok, Transaction.validated()} | {:error, :not_found}
  def get_last_transaction(address) do
    case Storage.last_transaction_address(address) do
      {:ok, last_address} ->
        search_transaction(last_address)

      {:error, :not_found} ->
        {:ok, %Node{network_patch: patch}} = P2P.node_info()

        address
        |> Election.storage_nodes()
        |> P2P.nearest_nodes(patch)
        |> List.first()
        |> P2P.send_message({:get_last_transaction, address})
    end
  end

  @doc """
  Retrieve the balance from an address.

  If the current node is a storage of this address, it will perform a fast lookup
  Otherwise it will request the closest storage node about it
  """
  @spec get_balance(binary) :: float()
  def get_balance(address) do
    storage_nodes = Election.storage_nodes(address)

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      Storage.balance(address)
    else
      {:ok, %Node{network_patch: patch}} = P2P.node_info()

      storage_nodes
      |> P2P.nearest_nodes(patch)
      |> List.first()
      |> P2P.send_message({:get_balance, address})
    end
  end

  @doc """
  Request to fetch the unspent
  """
  @spec get_transaction_inputs(Crypto.key()) :: list(UnspentOutput.t())
  def get_transaction_inputs(address) do
    storage_nodes = Election.storage_nodes(address)

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      Storage.get_inputs(address)
    else
      {:ok, %Node{network_patch: patch}} = P2P.node_info()

      storage_nodes
      |> P2P.nearest_nodes(patch)
      |> List.first()
      |> P2P.send_message({:get_inputs, address})
    end
  end

  @doc """
  Retrieve a transaction chain based on an address
  """
  @spec get_transaction_chain(binary()) :: list(Transaction.validated())
  def get_transaction_chain(address) do
    storage_nodes = Election.storage_nodes(address)

    if Crypto.node_public_key(0) in Enum.map(storage_nodes, & &1.first_public_key) do
      Storage.get_transaction_chain(address)
    else
      {:ok, %Node{network_patch: patch}} = P2P.node_info()

      storage_nodes
      |> P2P.nearest_nodes(patch)
      |> List.first()
      |> P2P.send_message({:get_transaction_chain, address})
    end
  end
end
