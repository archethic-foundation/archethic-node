defmodule UnirisNetwork do
  @moduledoc """
  Uniris's network supports a supervised P2P communication helpful to determine a local P2P view of the network and node shared secrets
  which handle authorization and access - preventing malicious nodes to validate transaction.

  During the node bootstraping, the node shared secrets and node listing are loading in memory into specific processes
  from the transaction chain to enable a fast read and processing.

  This module provides interface to get the node shared secrets, the network nodes and communicate with them throught P2P requests.

  """

  alias UnirisNetwork.Node
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisNetwork.P2P.Request
  alias UnirisCrypto, as: Crypto
  alias UnirisNetwork.P2P.Client
  alias UnirisNetwork.P2P.Atomic
  alias UnirisNetwork.SharedSecretStore
  alias UnirisNetwork.NodeStore

  @doc """
  Get the storage nonce used in the storage node election

  This nonce should not change to preserve the discoverabiliy of nodes tIt will be loaded during the node bootstraping.

  """
  @spec storage_nonce() :: binary()
  def storage_nonce() do
    SharedSecretStore.storage_nonce()
  end

  @doc """
  Get the daily nonce used in the validation node election.

  This nonce will change everyday through the process of renewal of node shared secrets.

  """
  @spec daily_nonce() :: binary()
  def daily_nonce() do
    SharedSecretStore.daily_nonce()
  end

  @doc """
  Retrieve the origin public keys used to determine the proof of work.
  """
  @spec origin_public_keys() :: list(binary())
  def origin_public_keys() do
    SharedSecretStore.origin_public_keys()
  end

  @doc """
  Get the list of node in the network

  This list is loaded on the node bootstraping from the TransactionChains of everynode and is changed when nodes are added or evicted
  through the node shared secret renewal.
  """
  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    NodeStore.list_nodes()
  end

  @doc """
  Retrieve node information from its public key.
  """
  @spec node_info(public_key :: <<_::264>>) :: Node.t() | {:error, :node_not_exists}
  def node_info(<<public_key::binary-33>>) do
    NodeStore.fetch_node(public_key)
  end

  @doc """
  Request atomically the download of a specific transaction.
  """
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

  @doc """
  Request atomically the download of a transaction chain.
  """
  @spec download_transaction_chain(storage_nodes :: list(Node.t()), address :: binary()) ::
          {:ok, list(Transaction.validated()), list(Node.t())}
          | {:error, :transaction_chain_not_exists}
          | {:error, :consensus_not_reached}
  def download_transaction_chain(storage_nodes, address)
      when is_list(storage_nodes) and is_binary(address) do
    Atomic.call(storage_nodes, Request.get_transaction_and_utxo(address))
  end

  @doc """
  Request atomically the preparation of a transaction validation where validation nodes must acknowledge the validation request.
  """
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

  @doc """
  Request the cross validation of the coordinator stamp.
  """
  @spec cross_validate_stamp(binary(), ValidationStamp.t(), list(Node.t())) :: :ok
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

  @doc """
  Request atomically the storage of a transaction where storage nodes must acknowledge the storage request.
  """
  @spec store_transaction(list(Node.t()), Transaction.pending()) :: :ok
  def store_transaction(storage_nodes, tx = %Transaction{}) when is_list(storage_nodes) do
    request = Request.store_transaction(tx)
    Atomic.cast(storage_nodes, request)
  end
end
