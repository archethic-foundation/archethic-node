defmodule UnirisNetwork.DefaultImpl do
  @moduledoc false

  alias UnirisNetwork.Node
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisNetwork.P2P.Request
  alias UnirisCrypto, as: Crypto
  alias UnirisNetwork.P2P.Client
  alias UnirisNetwork.P2P.Atomic
  alias UnirisNetwork.SharedSecretStore
  

  @behaviour UnirisNetwork.Impl

  @impl true
  @spec storage_nonce() :: binary()
  def storage_nonce() do
    SharedSecretStore.storage_nonce()
  end

  @impl true
  @spec daily_nonce() :: binary()
  def daily_nonce() do
    SharedSecretStore.daily_nonce()
  end

  @impl true
  @spec origin_public_keys() :: list(binary())
  def origin_public_keys() do
    SharedSecretStore.origin_public_keys()
  end

  @impl true
  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    DynamicSupervisor.which_children(UnirisNetwork.NodeSupervisor)
    |> Task.async_stream(fn {:undefined, pid, _, _} -> :sys.get_state(pid) end)
    |> Enum.into([], fn {:ok, res} -> res end)
  end

  @impl true
  @spec node_info(binary()) :: {:ok, Node.t()} | {:error, :node_not_exists}
  def node_info(public_key) do
    case UnirisNetwork.NodeRegistry.lookup(public_key) do
      [{pid, _}] ->
        {:ok, Node.details(pid)}
      [] ->
        {:error, :node_not_exists}
    end
  end

  @impl true
  @spec download_transaction(storage_nodes :: list(Node.t()), address :: binary()) ::
          {:ok, Transaction.validated(), list(Node.t())}
          | {:error, :transaction_not_exists}
          | {:error, :consensus_not_reached}
  def download_transaction(storage_nodes, address)
      when is_list(storage_nodes) and is_binary(address) do
    Atomic.call(storage_nodes, Request.get_transaction(address))
  end

  @spec download_transaction_and_utxo(storage_nodes :: list(Node.t()), address :: binary()) ::
          {:ok, Transaction.validated(), list(), list(Node.t())} | {:error, :consenus_not_reached}
  def download_transaction_and_utxo(storage_nodes, address)
      when is_list(storage_nodes) and is_binary(address) do
    Atomic.call(storage_nodes, Request.get_transaction_chain(address))
  end

  @impl true
  @spec download_transaction_chain(storage_nodes :: list(Node.t()), address :: binary()) ::
          {:ok, list(Transaction.validated()), list(Node.t())}
          | {:error, :transaction_chain_not_exists}
          | {:error, :consensus_not_reached}
  def download_transaction_chain(storage_nodes, address)
      when is_list(storage_nodes) and is_binary(address) do
    Atomic.call(storage_nodes, Request.get_transaction_and_utxo(address))
  end

  @impl true
  @spec prepare_validation(Transaction.pending(), list(Node.t())) ::
          :ok | {:error, :network_error}
  def prepare_validation(validation_nodes, tx = %Transaction{}) when is_list(validation_nodes) do
    {:ok, public_key} = Crypto.last_public_key(:node)

    request =
      Request.prepare_validation(
        tx,
        Enum.map(validation_nodes, & &1.last_public_key),
        public_key
      )

    Atomic.cast(validation_nodes, request)
  end

  @impl true
  @spec cross_validate_stamp(list(Node.t()), binary(), ValidationStamp.t()) :: :ok
  def cross_validate_stamp(validation_nodes, tx_address, stamp = %ValidationStamp{})
      when is_binary(tx_address) and is_list(validation_nodes) do
    request = Request.cross_validate_stamp(tx_address, stamp)

    Task.async_stream(validation_nodes, fn node ->
      case Client.send(node, request) do
        {:ok, _signature} ->
          # TODO: acknowledge the cross validation stamp
          :ok

        {:ok, _signature, _inconsistencies} ->
          # TODO: acknowledge the cross_validation stamp and inconsistencies
          :ok
      end
    end)
    |> Stream.run()
  end

  @impl true
  @spec store_transaction(list(Node.t()), Transaction.pending()) :: :ok
  def store_transaction(storage_nodes, tx = %Transaction{}) when is_list(storage_nodes) do
    request = Request.store_transaction(tx)
    Atomic.cast(storage_nodes, request)
  end
  
end
