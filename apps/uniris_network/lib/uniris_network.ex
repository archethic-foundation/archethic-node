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

  @behaviour UnirisNetwork.Impl

  @doc """
  Get the storage nonce used in the storage node election

  This nonce should not change to preserve the discoverabiliy of nodes tIt will be loaded during the node bootstraping.

  """
  @impl true
  @spec storage_nonce() :: binary()
  def storage_nonce() do
    impl().storage_nonce()
  end

  @doc """
  Get the daily nonce used in the validation node election.

  This nonce will change everyday through the process of renewal of node shared secrets.

  """
  @impl true
  @spec daily_nonce() :: binary()
  def daily_nonce() do
    impl().daily_nonce()
  end

  @doc """
  Retrieve the origin public keys used to determine the proof of work.
  """
  @impl true
  @spec origin_public_keys() :: list(binary())
  def origin_public_keys() do
    impl().origin_public_keys()
  end

  @doc """
  Get the list of node in the networik

  This list is loaded on the node bootstraping from the TransactionChains of everynode and is changed when nodes are added or evicted
  through the node shared secret renewal.
  """
  @impl true
  @spec list_nodes() :: list(Node.t())
  def list_nodes() do
    impl().list_nodes()
  end

  @doc """
  Request atomically the download of a specific transaction.
  """
  @impl true
  @spec download_transaction(storage_nodes :: list(Node.t()), address :: binary()) ::
          {:ok, Transaction.validated(), list(Node.t())}
          | {:error, :transaction_not_exists}
          | {:error, :consensus_not_reached}
  def download_transaction(storage_nodes, address)
      when is_list(storage_nodes) and is_binary(address) do
    impl().download_transaction(storage_nodes, address)
  end

  @doc """
  Request atomically the download of specific transaction and the related unspent output transactions
  """
  @impl true
  @spec download_transaction_and_utxo(storage_nodes :: list(Node.t()), address :: binary()) ::
          {:ok, Transaction.validated(), list(), list(Node.t())} | {:error, :consenus_not_reached}
  def download_transaction_and_utxo(storage_nodes, address)
      when is_list(storage_nodes) and is_binary(address) do
    impl().download_transaction_and_utxo(storage_nodes, address)
  end

  @doc """
  Request atomically the download of a transaction chain.
  """
  @impl true
  @spec download_transaction_chain(storage_nodes :: list(Node.t()), address :: binary()) ::
          {:ok, list(Transaction.validated()), list(Node.t())}
          | {:error, :transaction_chain_not_exists}
          | {:error, :consensus_not_reached}
  def download_transaction_chain(storage_nodes, address)
      when is_list(storage_nodes) and is_binary(address) do
    impl().download_transaction_chain(storage_nodes, address)
  end

  @doc """
  Request atomically the preparation of a transaction validation where validation nodes must acknowledge the validation request.
  """
  @impl true
  @spec prepare_validation(list(Node.t()), Transaction.pending()) ::
          :ok | {:error, :network_error}
  def prepare_validation(validation_nodes, tx = %Transaction{}) when is_list(validation_nodes) do
    impl().prepare_validation(validation_nodes, tx)
  end

  @doc """
  Request the cross validation of the coordinator stamp.
  """
  @impl true
  @spec cross_validate_stamp(list(Node.t()), binary(), ValidationStamp.t()) :: :ok
  def cross_validate_stamp(validation_nodes, tx_address, stamp = %ValidationStamp{})
      when is_binary(tx_address) and is_list(validation_nodes) do
    impl().cross_validate_stamp(validation_nodes, tx_address, stamp)
  end

  @doc """
  Request atomically the storage of a transaction where storage nodes must acknowledge the storage request.
  """
  @impl true
  @spec store_transaction(list(Node.t()), Transaction.pending()) :: :ok
  def store_transaction(storage_nodes, tx = %Transaction{}) when is_list(storage_nodes) do
    impl().store_transaction(storage_nodes, tx)
  end

  defp impl(), do: Application.get_env(:uniris_network, :impl, __MODULE__.DefaultImpl)
end
