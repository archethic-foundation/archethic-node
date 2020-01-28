defmodule UnirisNetwork.Impl do
  @moduledoc false

  alias UnirisNetwork.Node
  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp

  @callback storage_nonce() :: binary()
  @callback daily_nonce() :: binary()
  @callback origin_public_keys() :: list(binary())
  @callback list_nodes() :: list(Node.t())
  @callback download_transaction(list(Node.t()), binary()) :: {:ok, Transaction.validated(), list(Node.t())} | {:error, :transaction_not_exists} | {:error, :consensus_not_reached}

  @callback download_transaction_and_utxo(list(Node.t()), binary()) :: {:ok, Transaction.validated(), list(), list(Node.t())} | {:error, :consensus_not_reached}

  @callback download_transaction_chain(list(Node.t()), binary()) :: {:ok, list(Transaction.validated())} | {:error, :transaction_chain_not_exists} | {:consensus_not_reached}

  @callback prepare_validation(Transaction.pending(), list(Node.t())) :: :ok | {:error, :network_error}

  @callback cross_validate_stamp(list(Node.t()), binary(), ValidationStamp.t()) :: :ok

  @callback store_transaction(list(Node.t()), Transaction.validated()) :: :ok
end
